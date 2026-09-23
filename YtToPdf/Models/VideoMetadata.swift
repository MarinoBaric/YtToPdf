import Foundation

/// A caption track YouTube offers for a video.
nonisolated struct CaptionTrack: Codable, Sendable, Hashable, Identifiable {
    /// The key yt-dlp uses for this track, passed back to `--sub-langs` (e.g. `en`, `en-orig`).
    var key: String
    /// The track's language without yt-dlp's `-orig` suffix (e.g. `en`, `pt-BR`).
    var languageCode: String
    var name: String
    var isAutomatic: Bool

    var id: String { "\(isAutomatic ? "auto" : "manual"):\(key)" }

    /// The primary language subtag, so `en-US` and `en` count as the same language.
    var baseLanguage: String { Self.baseLanguage(of: languageCode) }

    static func baseLanguage(of code: String) -> String {
        code.split(separator: "-").first.map { $0.lowercased() } ?? code.lowercased()
    }
}

/// The subset of `yt-dlp -J` output that YtToPdf uses.
nonisolated struct VideoMetadata: Codable, Sendable, Hashable, Identifiable {
    var id: String
    var title: String
    var channel: String
    var duration: TimeInterval
    var uploadDate: Date?
    var thumbnailURL: URL?
    var webpageURL: URL
    /// The spoken language YouTube reports for the video, if any.
    var languageCode: String?
    var manualCaptions: [CaptionTrack]
    /// Speech-recognition tracks in the video's original language(s); machine translations are excluded.
    var automaticCaptions: [CaptionTrack]

    var hasCaptions: Bool {
        !manualCaptions.isEmpty || !automaticCaptions.isEmpty
    }
}
