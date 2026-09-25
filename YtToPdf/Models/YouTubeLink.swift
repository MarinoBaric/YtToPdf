import Foundation

/// A validated link to a single YouTube video.
///
/// Accepts `youtube.com/watch?v=`, `youtu.be/`, `/shorts/`, `/live/`, `/embed/` and `/v/`
/// links on any YouTube host, with or without a scheme and extra query parameters.
nonisolated struct YouTubeLink: Hashable, Sendable {
    let videoID: String

    init?(videoID: String) {
        guard Self.isValidID(videoID) else { return nil }
        self.videoID = videoID
    }

    init?(string: String) {
        var trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.contains("://") { trimmed = "https://" + trimmed }

        guard let components = URLComponents(string: trimmed),
              let host = components.host?.lowercased(),
              let id = Self.videoID(host: host, components: components)
        else { return nil }
        self.init(videoID: id)
    }

    var watchURL: URL {
        // Only [A-Za-z0-9_-] can reach here, so the URL is always well formed.
        URL(string: "https://www.youtube.com/watch?v=\(videoID)") ?? URL(filePath: "/")
    }

    /// A link that starts playback at `seconds`, used for clickable timestamps.
    func watchURL(at seconds: TimeInterval) -> URL {
        let whole = max(0, Int(seconds.rounded(.down)))
        return URL(string: "https://www.youtube.com/watch?v=\(videoID)&t=\(whole)s") ?? watchURL
    }

    // MARK: - Parsing

    private static let youTubeHosts: Set<String> = [
        "youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com",
        "youtube-nocookie.com", "www.youtube-nocookie.com",
    ]

    private static let pathPrefixes = ["shorts", "live", "embed", "v", "e"]

    private static func videoID(host: String, components: URLComponents) -> String? {
        let pathParts = components.path.split(separator: "/").map(String.init)

        if host == "youtu.be" || host == "www.youtu.be" {
            return pathParts.first
        }
        guard youTubeHosts.contains(host) else { return nil }

        if pathParts.first == "watch" || pathParts.isEmpty {
            return components.queryItems?.first { $0.name == "v" }?.value
        }
        if pathParts.count >= 2, pathPrefixes.contains(pathParts[0]) {
            return pathParts[1]
        }
        return nil
    }

    private static func isValidID(_ id: String) -> Bool {
        id.count == 11 && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }
}
