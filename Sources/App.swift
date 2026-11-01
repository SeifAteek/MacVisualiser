import MetalKit
import SwiftUI

struct Settings: Codable, Equatable {
    var mode = 0
    var palette = 0
    var autoCycle = true
    var cycleSeconds: Double = 30
    var cycleOnBeat = true
    var randomizeOnCycle = false
    var gain: Float = 1
    var smoothing: Float = 0.6
    var beatSensitivity: Float = 0.5
    var speed: Float = 1
    var shake: Float = 0.2
    var trails: Float = 0.6
    var fbZoom: Float = 0.3
    var fbRotate: Float = 0
    var fbHue: Float = 0
    var symmetry = 0
    var bloom: Float = 0.7
    var chroma: Float = 0.3
    var flash: Float = 0.3
    var grain: Float = 0.15
    var vignette: Float = 0.5
    var hue: Float = 0
    var hueCycle = false
    var renderScale: Float = 1
    var showFPS = false
}

final class Model: ObservableObject {
    static let modes = ["Nebula", "Tunnel", "Radial", "Julia", "Oscilloscope", "Hyperspace",
                        "Plasma", "Equalizer", "Orb", "Aurora", "Synthwave"]

    @Published var s: Settings {
        didSet { if let d = try? JSONEncoder().encode(s) { UserDefaults.standard.set(d, forKey: "settings") } }
    }
    @Published var panel = true
    @Published var toast: String?
    @Published var fps = 0
    @Published var meters: [Float] = [0, 0, 0, 0]
    @Published var audioError: String?
    private var toastID = 0

    init() {
        s = UserDefaults.standard.data(forKey: "settings").flatMap { try? JSONDecoder().decode(Settings.self, from: $0) } ?? Settings()
    }

    func step(_ d: Int) { s.mode = (s.mode + d + Self.modes.count) % Self.modes.count }

    func randomize() {
        s.mode = Int.random(in: 0..<Self.modes.count)
        s.palette = Int.random(in: 0..<palettes.count)
        s.trails = .random(in: 0...0.92)
        s.fbZoom = .random(in: -1...1)
        s.fbRotate = .random(in: -1...1)
        s.fbHue = Bool.random() ? 0 : .random(in: -1...1)
        s.symmetry = [0, 0, 0, 2, 3, 4, 5, 6, 8].randomElement()!
        s.bloom = .random(in: 0.2...1.4)
        s.chroma = .random(in: 0...0.8)
    }

    func say(_ text: String) {
        toastID += 1
        let id = toastID
        withAnimation { toast = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { if self.toastID == id { withAnimation { self.toast = nil } } }
    }

    func togglePanel() {
        withAnimation(.easeOut(duration: 0.25)) { panel.toggle() }
        if !panel { NSCursor.setHiddenUntilMouseMoves(true) }
    }

    /// Returns true when the key was handled.
    func handle(_ e: NSEvent) -> Bool {
        switch e.keyCode {
        case 124: step(1); return true   // →
        case 123: step(-1); return true  // ←
        default: break
        }
        guard let c = e.charactersIgnoringModifiers?.lowercased(), !e.modifierFlags.contains(.command) else { return false }
        switch c {
        case " ": step(1)
        case "h": togglePanel()
        case "f": NSApp.keyWindow?.toggleFullScreen(nil)
        case "p": s.palette = (s.palette + 1) % palettes.count; say(palettes[s.palette].name)
        case "a": s.autoCycle.toggle(); say("Auto-pilot \(s.autoCycle ? "on" : "off")")
        case "r": randomize()
        case "k": s.symmetry = [0, 2, 3, 4, 5, 6, 8, 12].drop { $0 <= s.symmetry }.first ?? 0
                  say(s.symmetry == 0 ? "Kaleidoscope off" : "Kaleidoscope ×\(s.symmetry)")
        case "t": s.trails = s.trails > 0 ? 0 : 0.6; say(s.trails > 0 ? "Trails on" : "Trails off")
        case "0"..."9":
            let i = c == "0" ? 9 : Int(c)! - 1
            if i < Self.modes.count { s.mode = i }
        default: return false
        }
        return true
    }
}

@main
struct VisualizerApp: App {
    @StateObject private var model = Model()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 640, minHeight: 400)
                .onAppear {
                    NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
                        // Let text fields keep their keys.
                        if NSApp.keyWindow?.firstResponder is NSText { return e }
                        return model.handle(e) ? nil : e
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
    }
}

struct MetalView: NSViewRepresentable {
    let model: Model
    final class Coordinator { var renderer: Renderer? }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> MTKView {
        let v = MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        v.colorPixelFormat = .bgra8Unorm
        v.preferredFramesPerSecond = 120
        let r = Renderer(view: v, model: model)
        context.coordinator.renderer = r
        v.delegate = r
        return v
    }

    func updateNSView(_ nsView: MTKView, context: Context) {}
}

struct ContentView: View {
    @EnvironmentObject var model: Model

    var body: some View {
        ZStack {
            Color.black
            MetalView(model: model)
            if let t = model.toast {
                Text(t)
                    .font(.system(size: 34, weight: .ultraLight, design: .rounded))
                    .tracking(8)
                    .foregroundStyle(.white.opacity(0.85))
                    .shadow(color: .black.opacity(0.6), radius: 12)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 60)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
            if model.s.showFPS {
                Text("\(model.fps) fps")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.leading, 12).padding(.top, 32)
                    .allowsHitTesting(false)
            }
            if model.panel {
                ControlPanel()
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .ignoresSafeArea()
    }
}

struct ControlPanel: View {
    @EnvironmentObject var model: Model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                section("Scene") {
                    Picker("Mode", selection: $model.s.mode) {
                        ForEach(Model.modes.indices, id: \.self) { i in Text("\(i < 9 ? "\(i + 1)" : i == 9 ? "0" : "–")  \(Model.modes[i])").tag(i) }
                    }
                    Picker("Palette", selection: $model.s.palette) {
                        ForEach(palettes.indices, id: \.self) { Text(palettes[$0].name).tag($0) }
                    }
                    HStack {
                        Button("◀︎ Prev") { model.step(-1) }
                        Button("Next ▶︎") { model.step(1) }
                        Spacer()
                        Button("🎲 Randomize") { model.randomize() }
                    }
                }
                section("Auto-pilot") {
                    Toggle("Cycle scenes", isOn: $model.s.autoCycle)
                    row("Every", "\(Int(model.s.cycleSeconds))s") { Slider(value: $model.s.cycleSeconds, in: 5...120) }
                    Toggle("Switch on the beat", isOn: $model.s.cycleOnBeat)
                    Toggle("Randomize everything on switch", isOn: $model.s.randomizeOnCycle)
                }
                section("Audio") {
                    slider("Sensitivity", $model.s.gain, 0.2...3)
                    slider("Smoothing", $model.s.smoothing, 0...0.95)
                    slider("Beat sensitivity", $model.s.beatSensitivity, 0...1)
                }
                section("Motion") {
                    slider("Speed", $model.s.speed, 0...3)
                    slider("Beat shake", $model.s.shake, 0...1)
                }
                section("Feedback") {
                    slider("Trails", $model.s.trails, 0...0.98)
                    slider("Zoom", $model.s.fbZoom, -1...1)
                    slider("Spin", $model.s.fbRotate, -1...1)
                    slider("Color drift", $model.s.fbHue, -1...1)
                    Picker("Kaleidoscope", selection: $model.s.symmetry) {
                        Text("Off").tag(0)
                        ForEach([2, 3, 4, 5, 6, 8, 12], id: \.self) { Text("×\($0)").tag($0) }
                    }
                }
                section("Post-processing") {
                    slider("Bloom", $model.s.bloom, 0...2)
                    slider("Chromatic aberration", $model.s.chroma, 0...1)
                    slider("Beat flash", $model.s.flash, 0...1)
                    slider("Film grain", $model.s.grain, 0...1)
                    slider("Vignette", $model.s.vignette, 0...1)
                    slider("Hue shift", $model.s.hue, -3.14...3.14)
                    Toggle("Cycle hue", isOn: $model.s.hueCycle)
                }
                section("Display") {
                    slider("Render scale", $model.s.renderScale, 0.4...1)
                    Toggle("Show FPS", isOn: $model.s.showFPS)
                    HStack {
                        Button("Fullscreen") { NSApp.keyWindow?.toggleFullScreen(nil) }
                        Spacer()
                        Button("Reset all") { model.s = Settings() }
                    }
                }
                Text("Space/→ next · ← prev · 1–0 scene · P palette · R randomize · K kaleidoscope · T trails · A auto-pilot · F fullscreen · H hide panel")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding(18)
        }
        .frame(width: 320)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(12)
        .padding(.top, 20)
        .environment(\.colorScheme, .dark)
        .controlSize(.small)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("VISUALIZER").font(.system(size: 13, weight: .semibold)).tracking(4)
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(0..<3, id: \.self) { i in
                    VStack(spacing: 3) {
                        Capsule().fill(.white.opacity(0.1)).frame(width: 60, height: 6)
                            .overlay(alignment: .leading) {
                                Capsule().fill(.white.opacity(0.8)).frame(width: 60 * CGFloat(min(model.meters[i], 1)), height: 6)
                            }
                        Text(["Bass", "Mid", "Treble"][i]).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Circle().fill(.white.opacity(Double(0.15 + model.meters[3] * 0.85))).frame(width: 10, height: 10).padding(.bottom, 14)
            }
            if let err = model.audioError {
                Text(err).font(.caption).foregroundStyle(.red)
            } else if model.meters[0] + model.meters[1] + model.meters[2] < 0.01 {
                Text("Silent. Play something — if it stays silent, allow Visualizer in System Settings › Privacy & Security › Screen & System Audio Recording (System Audio Recording Only).")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(2).foregroundStyle(.secondary)
            content()
        }
    }

    private func row<C: View>(_ label: String, _ value: String, @ViewBuilder _ control: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack { Text(label); Spacer(); Text(value).monospacedDigit().foregroundStyle(.secondary) }.font(.caption)
            control()
        }
    }

    private func slider(_ label: String, _ v: Binding<Float>, _ range: ClosedRange<Float>) -> some View {
        row(label, String(format: "%.2f", v.wrappedValue)) { Slider(value: v, in: range) }
    }
}
