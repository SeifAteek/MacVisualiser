import Foundation

/// A "vibe": which scenes, palettes and effect ranges suit a kind of music.
/// Scene and palette numbers index `Model.modes` and `palettes`.
struct Profile: Equatable {
    let name: String
    let scenes: [Int]
    let palettes: [Int]
    let trails: ClosedRange<Float>, zoom: ClosedRange<Float>, spin: ClosedRange<Float>
    let flash: Float, shake: Float
    let symmetry: [Int]
}

enum Vibe {
    // Scenes: 0 Nebula 1 Tunnel 2 Radial 3 Julia 4 Oscilloscope 5 Hyperspace 6 Plasma 7 Equalizer 8 Orb 9 Aurora 10 Synthwave
    // Palettes: 0 Spectrum 1 Sunset 2 Ocean 3 Inferno 4 Acid 5 Glacier 6 Synthwave 7 Pastel 8 Gold 9 Toxic 10 Mono
    static let retro = Profile(name: "Retro", scenes: [10, 7, 1, 2], palettes: [6, 1, 4],
                               trails: 0.4...0.8, zoom: 0.1...0.6, spin: -0.2...0.2, flash: 0.4, shake: 0.3, symmetry: [0, 0, 0, 2])
    static let rave = Profile(name: "Rave", scenes: [1, 5, 2, 7, 6, 0], palettes: [4, 0, 6, 9],
                              trails: 0.5...0.9, zoom: 0.3...1, spin: -0.6...0.6, flash: 0.5, shake: 0.4, symmetry: [0, 0, 4, 6, 8])
    static let heavy = Profile(name: "Heavy", scenes: [7, 2, 8, 10, 1], palettes: [3, 8, 6, 0],
                               trails: 0.3...0.7, zoom: 0...0.5, spin: -0.2...0.2, flash: 0.35, shake: 0.6, symmetry: [0, 0, 0, 2])
    static let loud = Profile(name: "Loud", scenes: [1, 7, 5, 6, 3], palettes: [3, 10, 4, 0],
                              trails: 0.4...0.8, zoom: 0.2...0.8, spin: -0.4...0.4, flash: 0.6, shake: 0.5, symmetry: [0, 0, 2, 3])
    static let calm = Profile(name: "Calm", scenes: [0, 9, 3, 8, 4], palettes: [5, 2, 7, 1],
                              trails: 0.7...0.95, zoom: -0.2...0.3, spin: -0.15...0.15, flash: 0, shake: 0, symmetry: [0, 0, 0, 6])
    static let bright = Profile(name: "Bright", scenes: [2, 6, 0, 10, 9, 8], palettes: [1, 7, 0, 6],
                                trails: 0.4...0.8, zoom: 0...0.6, spin: -0.3...0.3, flash: 0.3, shake: 0.2, symmetry: [0, 0, 3, 5, 6])

    // First match wins, so the more specific families come first ("synthpop" before "pop", "indie rock" hits "rock" before "indie").
    private static let genres: [(Profile, [String])] = [
        (retro, ["synthwave", "retrowave", "outrun", "80s", "disco", "new wave", "synthpop", "vaporwave"]),
        (rave, ["electronic", "electro", "dance", "edm", "house", "techno", "trance", "dubstep", "drum", "bass", "garage", "hardstyle", "rave", "club"]),
        (heavy, ["hip-hop", "hip hop", "rap", "trap", "r&b", "rnb", "drill", "grime"]),
        (loud, ["rock", "metal", "punk", "grunge", "hardcore", "emo", "alternative"]),
        (calm, ["ambient", "classical", "jazz", "lo-fi", "lofi", "chill", "new age", "soundtrack", "score", "piano", "acoustic",
                "folk", "blues", "singer/songwriter", "instrumental", "meditation", "sleep"]),
        (bright, ["pop", "indie", "latin", "reggae", "funk", "soul", "country", "afro", "world"]),
    ]

    static func profile(genre: String?) -> Profile? {
        guard let g = genre?.lowercased(), !g.isEmpty else { return nil }
        return genres.first { $0.1.contains { g.contains($0) } }?.0
    }

    /// Fallback when there's no genre: judge the vibe from the sound itself.
    // shortcut: thresholds are hand-picked, not fitted to labelled music; tune if vibes feel off.
    static func profile(bpm: Float, energy: Float, brightness: Float) -> Profile {
        if energy < 0.3 || (bpm > 0 && bpm < 85) { return calm }
        if bpm >= 118 && energy > 0.5 { return brightness > 0.45 ? rave : loud }
        return brightness < 0.35 ? heavy : bright
    }

    /// Tempo from recent beat-to-beat intervals (seconds), folded into a plausible 75–180 BPM range.
    static func bpm(_ intervals: [Float]) -> Float {
        guard intervals.count >= 4 else { return 0 }
        var b = 60 / intervals.sorted()[intervals.count / 2]
        while b < 75 { b *= 2 }
        while b > 180 { b /= 2 }
        return b
    }
}
