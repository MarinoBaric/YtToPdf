import Foundation

/// Turns `yt-dlp -J` output into `VideoMetadata`.
nonisolated enum MetadataDecoder {
    static func decode(_ data: Data) throws(YouTubeError) -> VideoMetadata {
        let raw: RawVideo
        do {
            raw = try JSONDecoder().decode(RawVideo.self, from: data)
        } catch {
            throw .malformedOutput("The video info couldn't be parsed.")
        }

        if raw.liveStatus == "is_live" || raw.liveStatus == "is_upcoming" {
            throw .liveOrUpcoming
        }
        guard let link = YouTubeLink(videoID: raw.id) else {
            throw .malformedOutput("yt-dlp returned an unexpected video ID.")
        }

        return VideoMetadata(
            id: raw.id,
            title: raw.title ?? "Untitled video",
            channel: raw.channel ?? raw.uploader ?? "Unknown channel",
            duration: raw.duration ?? 0,
            uploadDate: raw.uploadDate.flatMap(parseUploadDate),
            thumbnailURL: raw.thumbnail.flatMap(URL.init(string:)),
            webpageURL: link.watchURL,
            languageCode: raw.language,
            manualCaptions: manualTracks(raw.subtitles ?? [:]),
            automaticCaptions: automaticTracks(raw.automaticCaptions ?? [:], videoLanguage: raw.language)
        )
    }

    // MARK: - Caption tracks

    private static let originalSuffix = "-orig"

    private static func manualTracks(_ subtitles: [String: [RawSubtitleFormat]]) -> [CaptionTrack] {
        subtitles
            .filter { key, formats in key != "live_chat" && formats.contains { $0.ext == "json3" } }
            .map { key, formats in
                CaptionTrack(key: key, languageCode: key, name: displayName(key: key, formats: formats), isAutomatic: false)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// YouTube lists ~150 machine-translated "automatic" tracks. Only the `-orig` ones are real
    /// speech recognition, so keep those. Older responses have no `-orig` keys; then fall back to
    /// the track matching the video's language.
    private static func automaticTracks(_ captions: [String: [RawSubtitleFormat]], videoLanguage: String?) -> [CaptionTrack] {
        let usable = captions.filter { _, formats in formats.contains { $0.ext == "json3" } }
        var originals = usable.filter { $0.key.hasSuffix(originalSuffix) }

        if originals.isEmpty, let videoLanguage {
            let base = CaptionTrack.baseLanguage(of: videoLanguage)
            if let match = usable.first(where: { $0.key == videoLanguage })
                ?? usable.first(where: { CaptionTrack.baseLanguage(of: $0.key) == base }) {
                originals = [match.key: match.value]
            }
        }

        return originals
            .map { key, formats in
                CaptionTrack(
                    key: key,
                    languageCode: key.hasSuffix(originalSuffix) ? String(key.dropLast(originalSuffix.count)) : key,
                    name: displayName(key: key, formats: formats),
                    isAutomatic: true
                )
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func displayName(key: String, formats: [RawSubtitleFormat]) -> String {
        let reported = formats.lazy.compactMap(\.name).first { !$0.isEmpty }
        let cleaned = reported?.replacingOccurrences(of: " (Original)", with: "")
        let code = key.hasSuffix(originalSuffix) ? String(key.dropLast(originalSuffix.count)) : key
        return cleaned ?? Locale.current.localizedString(forIdentifier: code) ?? code
    }

    // MARK: - Dates

    private static func parseUploadDate(_ value: String) -> Date? {
        guard value.count == 8,
              let year = Int(value.prefix(4)),
              let month = Int(value.dropFirst(4).prefix(2)),
              let day = Int(value.suffix(2))
        else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))
    }
}

// MARK: - Raw yt-dlp JSON

nonisolated private struct RawVideo: Decodable {
    var id: String
    var title: String?
    var channel: String?
    var uploader: String?
    var duration: Double?
    var uploadDate: String?
    var thumbnail: String?
    var language: String?
    var liveStatus: String?
    var subtitles: [String: [RawSubtitleFormat]]?
    var automaticCaptions: [String: [RawSubtitleFormat]]?

    enum CodingKeys: String, CodingKey {
        case id, title, channel, uploader, duration, thumbnail, language, subtitles
        case uploadDate = "upload_date"
        case liveStatus = "live_status"
        case automaticCaptions = "automatic_captions"
    }
}

nonisolated private struct RawSubtitleFormat: Decodable {
    var ext: String?
    var name: String?
}
