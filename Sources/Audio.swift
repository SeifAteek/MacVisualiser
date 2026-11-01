import Accelerate
import AudioToolbox
import CoreAudio
import Foundation

/// Captures everything the Mac is playing via a Core Audio process tap (macOS 14.2+).
final class SystemAudio {
    private let lock = NSLock()
    private var ring = [Float](repeating: 0, count: 16384)
    private var writeIndex = 0
    private(set) var sampleRate: Double = 48000

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?

    // The tap and aggregate are private to this process, so Core Audio removes them when we exit.
    func start() throws {
        let desc = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        desc.uuid = UUID()
        desc.muteBehavior = .unmuted
        desc.isPrivate = true
        try check(AudioHardwareCreateProcessTap(desc, &tapID), "create process tap")

        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        try check(AudioObjectGetPropertyData(tapID, &addr, 0, nil, &size, &asbd), "read tap format")
        sampleRate = asbd.mSampleRate

        let outputUID = try defaultOutputUID()
        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Visualizer Tap",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true,
                                               kAudioSubTapUIDKey: desc.uuid.uuidString]],
        ]
        try check(AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID), "create aggregate device")

        try check(AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, nil) { [weak self] _, input, _, _, _ in
            self?.push(UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input)))
        }, "create IO proc")
        try check(AudioDeviceStart(aggregateID, procID), "start device")
    }

    /// Downmixes every channel of every buffer to mono into the ring.
    private func push(_ abl: UnsafeMutableAudioBufferListPointer) {
        guard let first = abl.first, first.mNumberChannels > 0 else { return }
        let frames = Int(first.mDataByteSize) / (4 * Int(first.mNumberChannels))
        let totalChannels = Float(abl.reduce(0) { $0 + Int($1.mNumberChannels) })
        lock.lock(); defer { lock.unlock() }
        for f in 0..<frames {
            var sum: Float = 0
            for buf in abl {
                guard let p = buf.mData?.assumingMemoryBound(to: Float.self) else { continue }
                let ch = Int(buf.mNumberChannels)
                for c in 0..<ch { sum += p[f * ch + c] }
            }
            ring[writeIndex] = sum / totalChannels
            writeIndex = (writeIndex + 1) & (ring.count - 1)
        }
    }

    /// Most recent `count` samples, oldest first.
    func latest(_ count: Int) -> [Float] {
        lock.lock(); defer { lock.unlock() }
        let start = (writeIndex - count + ring.count) & (ring.count - 1)
        return (0..<count).map { ring[(start + $0) & (ring.count - 1)] }
    }

    private func defaultOutputUID() throws -> String {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        try check(AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &device), "find output device")
        var uid: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        addr.mSelector = kAudioDevicePropertyDeviceUID
        try check(AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &uid), "read output device UID")
        return uid!.takeRetainedValue() as String
    }

    private func check(_ status: OSStatus, _ what: String) throws {
        if status != noErr { throw NSError(domain: "Audio", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Could not \(what) (OSStatus \(status))"]) }
    }
}

/// FFT → 256 log-spaced bands, band energies, beat detection, stabilized waveform.
final class Analyzer {
    static let bands = 256
    let n = 2048
    private let fft = vDSP.FFT(log2n: 11, radix: .radix2, ofType: DSPSplitComplex.self)!
    private let window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: 2048, isHalfWindow: false)
    private var real = [Float](repeating: 0, count: 1024)
    private var imag = [Float](repeating: 0, count: 1024)
    private var mags = [Float](repeating: 0, count: 1024)

    var spectrum = [Float](repeating: 0, count: bands)
    var wave = [Float](repeating: 0, count: bands)
    var bass: Float = 0, mid: Float = 0, treble: Float = 0, level: Float = 0
    var beat: Float = 0
    var beatCount: Float = 0
    private(set) var didBeat = false

    private var peak: Float = 0.5
    private var wavePeak: Float = 0.1
    private var bassAvg: Float = 0
    private var sinceBeat: Float = 1

    func update(_ samples: [Float], sampleRate: Double, dt: Float, gain: Float, smoothing: Float, beatSensitivity: Float) {
        let windowed = vDSP.multiply(samples, window)
        real.withUnsafeMutableBufferPointer { rp in
            imag.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                windowed.withUnsafeBytes { vDSP_ctoz($0.bindMemory(to: DSPComplex.self).baseAddress!, 2, &split, 1, 1024) }
                fft.forward(input: split, output: &split)
                vDSP_zvabs(&split, 1, &mags, 1, 1024)
            }
        }

        // Log-spaced bands 30 Hz – 16 kHz, in dB with a +3 dB/octave tilt so highs aren't invisible.
        let binHz = Float(sampleRate) / Float(n)
        let lo: Float = 30, hi: Float = 16000
        var raw = [Float](repeating: 0, count: Self.bands)
        var frameMax: Float = 0
        for i in 0..<Self.bands {
            let f0 = lo * pow(hi / lo, Float(i) / Float(Self.bands))
            let f1 = lo * pow(hi / lo, Float(i + 1) / Float(Self.bands))
            let b0 = f0 / binHz, b1 = f1 / binHz
            var m: Float
            if b1 - b0 < 1 {
                let k = min(Int(b0), 1022), t = b0 - Float(k)
                m = mags[k] * (1 - t) + mags[k + 1] * t
            } else {
                m = 0
                for k in Int(b0)...min(Int(b1), 1023) { m = max(m, mags[k]) }
            }
            let db = 20 * log10(m / Float(n) + 1e-9) + 3 * log2(f0 / 1000)
            let v = max(0, (db + 75) / 65)
            raw[i] = v
            frameMax = max(frameMax, v)
        }
        // Slow auto-gain so quiet and loud tracks both fill the screen.
        peak = max(peak * (1 - 0.15 * dt), frameMax, 0.35)
        let release = 1 - pow(smoothing, 0.35) * 0.9
        for i in 0..<Self.bands {
            let v = min(1.5, raw[i] / peak * gain)
            spectrum[i] += (v - spectrum[i]) * (v > spectrum[i] ? 0.7 : release)
        }

        func avg(_ a: Int, _ b: Int, _ src: [Float]) -> Float { src[a..<b].reduce(0, +) / Float(b - a) }
        bass = avg(0, 65, spectrum); mid = avg(65, 171, spectrum); treble = avg(171, 256, spectrum)
        level = (bass + mid + treble) / 3

        // Beat: raw bass energy jumps above its running average.
        let rawBass = avg(0, 50, raw) / peak * gain
        sinceBeat += dt
        didBeat = rawBass > bassAvg * (1.6 - 0.8 * beatSensitivity) && rawBass > 0.25 && sinceBeat > 0.25
        if didBeat { beat = 1; beatCount += 1; sinceBeat = 0 }
        bassAvg += (rawBass - bassAvg) * min(1, dt * 3)
        beat *= exp(-dt * 6)

        // Oscilloscope: start at a rising zero crossing so the wave stands still.
        var start = 0
        for i in 1..<(n - 1024) where samples[i - 1] < 0 && samples[i] >= 0 { start = i; break }
        var wp: Float = 0
        for i in 0..<Self.bands {
            let s = samples[start + i * 4]
            wave[i] = s
            wp = max(wp, abs(s))
        }
        wavePeak = max(wavePeak * (1 - 0.5 * dt), wp, 0.02)
        for i in 0..<Self.bands { wave[i] = wave[i] / wavePeak * min(gain, 1.5) }
    }
}
