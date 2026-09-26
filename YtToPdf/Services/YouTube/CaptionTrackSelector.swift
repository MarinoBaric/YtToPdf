import Foundation

/// Chooses which caption track to use for a language.
nonisolated enum CaptionTrackSelector {
    /// One entry per language that has any captions, in display order.
    struct LanguageOption: Hashable, Sendable, Identifiable {
        var languageCode: String
        var name: String
        var hasManual: Bool
        var hasAutomatic: Bool

        var id: String { languageCode }
    }

    static func languageOptions(for metadata: VideoMetadata) -> [LanguageOption] {
        var options: [String: LanguageOption] = [:]
        for track in metadata.manualCaptions + metadata.automaticCaptions {
            var option = options[track.languageCode]
                ?? LanguageOption(languageCode: track.languageCode, name: track.name, hasManual: false, hasAutomatic: false)
            if track.isAutomatic { option.hasAutomatic = true } else { option.hasManual = true; option.name = track.name }
            options[track.languageCode] = option
        }
        return options.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The language to pre-select: the user's preference if offered, else the video's spoken
    /// language, else English, else whatever comes first.
    static func defaultLanguage(for metadata: VideoMetadata, preferred: String?) -> String? {
        let available = languageOptions(for: metadata).map(\.languageCode)
        let wanted = [preferred, metadata.languageCode, "en"].compactMap(\.self)
        for code in wanted {
            if let match = bestMatch(for: code, in: available) { return match }
        }
        return available.first
    }

    /// The track to download for `languageCode`. Falls back to the other kind of caption when
    /// the preferred kind doesn't exist for that language.
    static func track(for metadata: VideoMetadata, languageCode: String, preferManual: Bool) -> CaptionTrack? {
        let manual = metadata.manualCaptions.first { $0.languageCode == languageCode }
            ?? metadata.manualCaptions.first { $0.baseLanguage == CaptionTrack.baseLanguage(of: languageCode) }
        let automatic = metadata.automaticCaptions.first { $0.languageCode == languageCode }
            ?? metadata.automaticCaptions.first { $0.baseLanguage == CaptionTrack.baseLanguage(of: languageCode) }
        return preferManual ? (manual ?? automatic) : (automatic ?? manual)
    }

    private static func bestMatch(for code: String, in available: [String]) -> String? {
        if available.contains(code) { return code }
        let base = CaptionTrack.baseLanguage(of: code)
        return available.first { $0 == base } ?? available.first { CaptionTrack.baseLanguage(of: $0) == base }
    }
}
