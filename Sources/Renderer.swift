import MetalKit

// Field-for-field mirror of `struct U` in Shaders.metal.
struct Uniforms {
    var width: Float = 0, height: Float = 0, time: Float = 0, rtime: Float = 0
    var bass: Float = 0, mid: Float = 0, treble: Float = 0, level: Float = 0
    var beat: Float = 0, beatCount: Float = 0, mode: Float = 0, prevMode: Float = 0
    var mixT: Float = 1, hue: Float = 0, trails: Float = 0, fbZoom: Float = 0
    var fbRotate: Float = 0, fbHue: Float = 0, symmetry: Float = 0, bloom: Float = 0
    var chroma: Float = 0, grain: Float = 0, vignette: Float = 0, flash: Float = 0
    var shake: Float = 0, pad0: Float = 0, pad1: Float = 0, pad2: Float = 0
}

/// Cosine palettes: color(t) = a + b·cos(2π(c·t + d)).
let palettes: [(name: String, abcd: [SIMD4<Float>])] = [
    ("Spectrum", [[0.5, 0.5, 0.5, 0], [0.5, 0.5, 0.5, 0], [1, 1, 1, 0], [0, 0.33, 0.67, 0]]),
    ("Sunset", [[0.5, 0.5, 0.5, 0], [0.5, 0.5, 0.5, 0], [1, 1, 0.5, 0], [0.8, 0.9, 0.3, 0]]),
    ("Ocean", [[0.5, 0.5, 0.5, 0], [0.5, 0.5, 0.5, 0], [1, 0.7, 0.4, 0], [0, 0.15, 0.2, 0]]),
    ("Inferno", [[0.6, 0.3, 0.1, 0], [0.5, 0.35, 0.15, 0], [1, 1, 1, 0], [0, 0.1, 0.2, 0]]),
    ("Acid", [[0.5, 0.5, 0.5, 0], [0.5, 0.5, 0.5, 0], [2, 1, 0, 0], [0.5, 0.2, 0.25, 0]]),
    ("Glacier", [[0.4, 0.6, 0.8, 0], [0.3, 0.3, 0.25, 0], [1, 1, 1, 0], [0.1, 0.2, 0.3, 0]]),
    ("Synthwave", [[0.5, 0.35, 0.6, 0], [0.5, 0.35, 0.4, 0], [1, 1, 1, 0], [0.85, 0.25, 0.15, 0]]),
    ("Pastel", [[0.8, 0.8, 0.8, 0], [0.2, 0.2, 0.2, 0], [1, 1, 1, 0], [0, 0.33, 0.67, 0]]),
    ("Gold", [[0.6, 0.45, 0.2, 0], [0.4, 0.3, 0.15, 0], [1, 1, 1, 0], [0, 0.05, 0.1, 0]]),
    ("Toxic", [[0.3, 0.6, 0.3, 0], [0.3, 0.5, 0.3, 0], [1, 1, 1, 0], [0.3, 0.1, 0.5, 0]]),
    ("Mono", [[0.5, 0.5, 0.5, 0], [0.5, 0.5, 0.5, 0], [1, 1, 1, 0], [0, 0, 0, 0]]),
]

final class Renderer: NSObject, MTKViewDelegate {
    private let model: Model
    private let queue: MTLCommandQueue
    private let scenePSO, feedbackPSO, postPSO: MTLRenderPipelineState
    private let audio = SystemAudio()
    private let analyzer = Analyzer()

    private var sceneTex: MTLTexture?
    private var accum: [MTLTexture] = []
    private var flip = 0
    private var freshAccum = true

    private var time: Float = 0, rtime: Float = 0
    private var last = CACurrentMediaTime()
    private var currentMode = -1, prevMode = 0
    private var mixT: Float = 1
    private var palette = palettes[0].abcd
    private var cycleClock: Float = 0
    private var frames = 0, fpsClock = CACurrentMediaTime()

    init(view: MTKView, model: Model) {
        self.model = model
        let device = view.device!
        queue = device.makeCommandQueue()!
        let src = try! String(contentsOf: Bundle.main.url(forResource: "Shaders", withExtension: "metal")!, encoding: .utf8)
        let lib: MTLLibrary
        do { lib = try device.makeLibrary(source: src, options: nil) } catch { fatalError("Shader compile failed: \(error)") }
        func pso(_ frag: String, _ fmt: MTLPixelFormat) -> MTLRenderPipelineState {
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = lib.makeFunction(name: "vsQuad")
            d.fragmentFunction = lib.makeFunction(name: frag)
            d.colorAttachments[0].pixelFormat = fmt
            return try! device.makeRenderPipelineState(descriptor: d)
        }
        scenePSO = pso("fsScene", .rgba16Float)
        feedbackPSO = pso("fsFeedback", .rgba16Float)
        postPSO = pso("fsPost", view.colorPixelFormat)
        palette = palettes[model.s.palette].abcd
        super.init()
        do { try audio.start() } catch { model.audioError = error.localizedDescription }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    private func makeTextures(_ w: Int, _ h: Int, _ device: MTLDevice) {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: w, height: h, mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]
        d.storageMode = .private
        sceneTex = device.makeTexture(descriptor: d)
        let m = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: w, height: h, mipmapped: true)
        m.usage = [.renderTarget, .shaderRead]
        m.storageMode = .private
        accum = [device.makeTexture(descriptor: m)!, device.makeTexture(descriptor: m)!]
        freshAccum = true
    }

    private func pass(_ cb: MTLCommandBuffer, _ target: MTLTexture, _ pso: MTLRenderPipelineState, _ bind: (MTLRenderCommandEncoder) -> Void) {
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = target
        rpd.colorAttachments[0].loadAction = .dontCare
        rpd.colorAttachments[0].storeAction = .store
        let enc = cb.makeRenderCommandEncoder(descriptor: rpd)!
        enc.setRenderPipelineState(pso)
        bind(enc)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
    }

    func draw(in view: MTKView) {
        let s = model.s
        let now = CACurrentMediaTime()
        let dt = Float(min(now - last, 0.1))
        last = now

        let a = analyzer
        a.update(audio.latest(a.n), sampleRate: audio.sampleRate, dt: dt, gain: s.gain, smoothing: s.smoothing, beatSensitivity: s.beatSensitivity)
        rtime += dt
        time += dt * s.speed * (0.5 + a.level * 1.5) // the music drives the clock

        if s.mode != currentMode {
            if currentMode >= 0 { prevMode = currentMode; mixT = 0 }
            currentMode = s.mode
            model.say(Model.modes[s.mode])
        }
        mixT = min(1, mixT + dt / 1.5)

        if s.autoCycle {
            cycleClock += dt
            let due = cycleClock > Float(s.cycleSeconds)
            if due && (!s.cycleOnBeat || a.didBeat || cycleClock > Float(s.cycleSeconds) + 5) {
                cycleClock = 0
                if s.randomizeOnCycle { model.randomize() } else { model.step(1) }
            }
        } else { cycleClock = 0 }

        let target = palettes[s.palette].abcd
        for i in 0..<4 { palette[i] += (target[i] - palette[i]) * min(1, dt * 1.5) }

        let w = max(16, Int(view.drawableSize.width * CGFloat(s.renderScale)))
        let h = max(16, Int(view.drawableSize.height * CGFloat(s.renderScale)))
        if sceneTex?.width != w || sceneTex?.height != h { makeTextures(w, h, view.device!) }

        guard let drawable = view.currentDrawable, let rpd = view.currentRenderPassDescriptor,
              let cb = queue.makeCommandBuffer(), let sceneTex else { return }

        var u = Uniforms(width: Float(w), height: Float(h), time: time, rtime: rtime,
                         bass: a.bass, mid: a.mid, treble: a.treble, level: a.level,
                         beat: a.beat, beatCount: a.beatCount, mode: Float(currentMode), prevMode: Float(prevMode),
                         mixT: mixT, hue: s.hue + (s.hueCycle ? rtime * 0.15 : 0),
                         trails: freshAccum ? 0 : s.trails, fbZoom: s.fbZoom,
                         fbRotate: s.fbRotate, fbHue: s.fbHue, symmetry: Float(s.symmetry), bloom: s.bloom,
                         chroma: s.chroma, grain: s.grain, vignette: s.vignette, flash: s.flash, shake: s.shake)
        freshAccum = false
        let ulen = MemoryLayout<Uniforms>.stride
        let plen = MemoryLayout<SIMD4<Float>>.stride * 4

        pass(cb, sceneTex, scenePSO) { e in
            e.setFragmentBytes(&u, length: ulen, index: 0)
            e.setFragmentBytes(a.spectrum, length: Analyzer.bands * 4, index: 1)
            e.setFragmentBytes(a.wave, length: Analyzer.bands * 4, index: 2)
            e.setFragmentBytes(palette, length: plen, index: 3)
        }
        let src = accum[flip], dst = accum[1 - flip]
        flip ^= 1
        pass(cb, dst, feedbackPSO) { e in
            e.setFragmentBytes(&u, length: ulen, index: 0)
            e.setFragmentTexture(sceneTex, index: 0)
            e.setFragmentTexture(src, index: 1)
        }
        let blit = cb.makeBlitCommandEncoder()!
        blit.generateMipmaps(for: dst)
        blit.endEncoding()

        let enc = cb.makeRenderCommandEncoder(descriptor: rpd)!
        enc.setRenderPipelineState(postPSO)
        enc.setFragmentBytes(&u, length: ulen, index: 0)
        enc.setFragmentBytes(palette, length: plen, index: 3)
        enc.setFragmentTexture(dst, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
        cb.present(drawable)
        cb.commit()

        frames += 1
        if frames % 6 == 0 { model.meters = [a.bass, a.mid, a.treble, a.beat] }
        if now - fpsClock >= 1 { model.fps = Int(Double(frames) / (now - fpsClock)); frames = 0; fpsClock = now }
    }
}
