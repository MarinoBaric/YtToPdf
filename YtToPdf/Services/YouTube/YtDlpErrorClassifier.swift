import Foundation

/// Maps yt-dlp's stderr to a `YouTubeError` the UI can explain.
nonisolated enum YtDlpErrorClassifier {
    private static let rules: [(YouTubeError, [String])] = [
        (.privateVideo, ["private video"]),
        (.ageRestricted, ["confirm your age", "age-restricted", "age restricted", "inappropriate for some users"]),
        (.membersOnly, ["members-only", "join this channel"]),
        (.botCheck, ["not a bot"]),
        (.liveOrUpcoming, ["live event will begin", "premieres in", "this live stream recording is not available"]),
        (.unavailable, ["video unavailable", "video is unavailable", "has been removed", "is not available in your country",
                        "terminated", "does not exist"]),
        (.noNetwork, ["nodename nor servname", "failed to resolve", "name resolution", "network is unreachable",
                      "internet connection appears to be offline", "timed out", "connection refused", "no route to host",
                      "unable to download api page", "urlopen error"]),
        (.invalidURL, ["unsupported url", "is not a valid url"]),
        (.downloadBlocked, ["http error 403", "403: forbidden"]),
        (.ytDlpOutdated, ["latest version", "yt-dlp -u", "signature extraction failed", "nsig extraction failed",
                          "unable to extract", "please report this issue"]),
    ]

    static func classify(_ standardError: String) -> YouTubeError {
        let errorLines = standardError
            .split(whereSeparator: \.isNewline)
            .filter { $0.hasPrefix("ERROR:") }
        let haystack = (errorLines.isEmpty ? standardError : errorLines.joined(separator: "\n"))
            .lowercased()
            .replacingOccurrences(of: "’", with: "'")

        for (error, needles) in rules where needles.contains(where: haystack.contains) {
            return error
        }
        return .toolFailed(lastErrorMessage(errorLines.last.map(String.init) ?? standardError))
    }

    /// `ERROR: [youtube] abc: Something broke` → `Something broke`.
    private static func lastErrorMessage(_ line: String) -> String {
        var message = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if message.hasPrefix("ERROR:") { message = String(message.dropFirst(6)) }
        if let bracket = message.range(of: "] "), let colon = message.range(of: ": ", range: bracket.upperBound..<message.endIndex) {
            message = String(message[colon.upperBound...])
        }
        let trimmed = message.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "yt-dlp exited without explaining why." : trimmed
    }
}
