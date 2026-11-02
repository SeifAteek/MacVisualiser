// Self-checks for the autopilot's pure logic. Run by build.sh.
func check(_ ok: Bool, _ what: String) { precondition(ok, "FAILED: \(what)") }

check(Vibe.profile(genre: "Electronic")?.name == "Rave", "Electronic → Rave")
check(Vibe.profile(genre: "Dance")?.name == "Rave", "Dance → Rave")
check(Vibe.profile(genre: "Hip-Hop/Rap")?.name == "Heavy", "Hip-Hop/Rap → Heavy")
check(Vibe.profile(genre: "R&B/Soul")?.name == "Heavy", "R&B/Soul → Heavy")
check(Vibe.profile(genre: "Indie Rock")?.name == "Loud", "Indie Rock → Loud")
check(Vibe.profile(genre: "Indie Pop")?.name == "Bright", "Indie Pop → Bright")
check(Vibe.profile(genre: "Synthpop")?.name == "Retro", "Synthpop → Retro")
check(Vibe.profile(genre: "Soundtrack")?.name == "Calm", "Soundtrack → Calm")
check(Vibe.profile(genre: "Classical")?.name == "Calm", "Classical → Calm")
check(Vibe.profile(genre: "Polka") == nil, "unknown genre → nil")
check(Vibe.profile(genre: "") == nil && Vibe.profile(genre: nil) == nil, "no genre → nil")

check(abs(Vibe.bpm(Array(repeating: 0.469, count: 8)) - 128) < 1, "128 BPM")
check(abs(Vibe.bpm(Array(repeating: 0.938, count: 8)) - 128) < 1, "half-time kicks fold up to 128")
check(abs(Vibe.bpm([0.5, 0.5, 0.5, 0.9, 0.5]) - 120) < 1, "median ignores a missed beat")
check(Vibe.bpm([0.5, 0.5]) == 0, "too few beats → unknown")

check(Vibe.profile(bpm: 70, energy: 0.6, brightness: 0.5).name == "Calm", "slow → Calm")
check(Vibe.profile(bpm: 128, energy: 0.7, brightness: 0.5).name == "Rave", "fast, bright, loud → Rave")
check(Vibe.profile(bpm: 128, energy: 0.7, brightness: 0.3).name == "Loud", "fast, dark, loud → Loud")
check(Vibe.profile(bpm: 95, energy: 0.6, brightness: 0.3).name == "Heavy", "mid-tempo, bassy → Heavy")
print("pilot tests passed")
