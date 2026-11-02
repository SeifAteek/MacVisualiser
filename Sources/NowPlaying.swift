import AppKit

/// Reads the playing song from Music or Spotify and finds its genre.
/// macOS 15.4+ closed the system-wide Now Playing API to third-party apps, so browsers and other players aren't visible here;
/// the autopilot falls back to judging the vibe from the audio.
final class NowPlaying {
    struct Track: Equatable { var title: String, artist: String, genre: String? }

    var onChange: ((Track?) -> Void)?
    private var current: Track?
    private var timer: Timer?
    private let queue = DispatchQueue(label: "nowplaying") // AppleScript and lookups stay off the render thread
    private var genreCache: [String: String] = [:]          // touched only on `queue`

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.poll() }
        poll()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        update(nil)
    }

    private func poll() {
        queue.async { [weak self] in
            guard let self else { return }
            var t = Self.playing()
            if let x = t, x.genre == nil { t?.genre = self.lookupGenre(x) }
            DispatchQueue.main.async { if self.timer != nil { self.update(t) } }
        }
    }

    private func update(_ t: Track?) {
        guard t?.title != current?.title || t?.artist != current?.artist else { return }
        current = t
        onChange?(t)
    }

    /// Asks Music, then Spotify, only if already running (`tell application` would launch them).
    private static func playing() -> Track? {
        for (id, hasGenre) in [("com.apple.Music", true), ("com.spotify.client", false)]
        where !NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty {
            let genre = hasGenre ? " & \"\\n\" & (genre of current track)" : ""
            let src = "tell application id \"\(id)\" to if player state is playing then return (name of current track) & \"\\n\" & (artist of current track)\(genre)"
            var err: NSDictionary?
            guard let out = NSAppleScript(source: src)?.executeAndReturnError(&err).stringValue else { continue }
            let p = out.components(separatedBy: "\n")
            guard p.count >= 2, !p[0].isEmpty else { continue }
            return Track(title: p[0], artist: p[1], genre: p.count > 2 && !p[2].isEmpty ? p[2] : nil)
        }
        return nil
    }

    /// Apple's public iTunes Search API: no key needed. Failures are cached as "" so a song is looked up once.
    private func lookupGenre(_ t: Track) -> String? {
        let key = "\(t.artist)|\(t.title)"
        if let g = genreCache[key] { return g.isEmpty ? nil : g }
        var c = URLComponents(string: "https://itunes.apple.com/search")!
        c.queryItems = [.init(name: "term", value: "\(t.artist) \(t.title)"),
                        .init(name: "entity", value: "song"), .init(name: "limit", value: "1")]
        var genre = ""
        let done = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: URLRequest(url: c.url!, timeoutInterval: 5)) { data, _, _ in
            if let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let hit = (json["results"] as? [[String: Any]])?.first {
                genre = hit["primaryGenreName"] as? String ?? ""
            }
            done.signal()
        }.resume()
        done.wait()
        genreCache[key] = genre
        return genre.isEmpty ? nil : genre
    }
}
