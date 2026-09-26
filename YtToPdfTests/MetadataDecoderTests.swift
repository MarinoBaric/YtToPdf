import Foundation
import Testing
@testable import YtToPdf

@Suite("Metadata decoding and caption track selection")
struct MetadataDecoderTests {
    /// Shaped like `yt-dlp -J` output, trimmed to the fields YtToPdf reads plus some noise.
    private static let sample = Data("""
    {
      "id": "abcdefghijk",
      "title": "How Joinery Works",
      "channel": "Sample Workshop",
      "uploader": "sampleworkshop",
      "duration": 754,
      "upload_date": "20240315",
      "thumbnail": "https://i.ytimg.com/vi/abcdefghijk/maxresdefault.jpg",
      "language": "en-US",
      "live_status": "not_live",
      "formats": [{"format_id": "sb3"}],
      "subtitles": {
        "live_chat": [{"ext": "json", "name": "Live chat"}],
        "en": [{"ext": "vtt", "name": "English"}, {"ext": "json3", "name": "English"}],
        "de": [{"ext": "json3", "name": "German"}],
        "fr": [{"ext": "vtt", "name": "French"}]
      },
      "automatic_captions": {
        "en": [{"ext": "json3", "name": "English"}],
        "en-orig": [{"ext": "json3", "name": "English (Original)"}],
        "es-US-orig": [{"ext": "json3", "name": "Spanish (United States) (Original)"}],
        "hr": [{"ext": "json3", "name": "Croatian"}],
        "ja": [{"ext": "json3", "name": "Japanese"}]
      }
    }
    """.utf8)

    @Test func decodesCoreFields() throws {
        let metadata = try MetadataDecoder.decode(Self.sample)
        #expect(metadata.id == "abcdefghijk")
        #expect(metadata.title == "How Joinery Works")
        #expect(metadata.channel == "Sample Workshop")
        #expect(metadata.duration == 754)
        #expect(metadata.languageCode == "en-US")
        #expect(metadata.webpageURL.absoluteString == "https://www.youtube.com/watch?v=abcdefghijk")
        #expect(metadata.thumbnailURL?.host() == "i.ytimg.com")

        let date = try #require(metadata.uploadDate)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        #expect(calendar.dateComponents([.year, .month, .day], from: date) == DateComponents(year: 2024, month: 3, day: 15))
    }

    @Test func keepsOnlyJson3ManualTracksAndOriginalAutoTracks() throws {
        let metadata = try MetadataDecoder.decode(Self.sample)
        // Sorted by display name: English, German. French has no json3 and live chat isn't a caption.
        #expect(metadata.manualCaptions.map(\.key) == ["en", "de"])
        #expect(Set(metadata.automaticCaptions.map(\.key)) == ["en-orig", "es-US-orig"])

        let english = try #require(metadata.automaticCaptions.first { $0.key == "en-orig" })
        #expect(english.languageCode == "en")
        #expect(english.name == "English")
        #expect(english.isAutomatic)
    }

    @Test func fallsBackToVideoLanguageWhenNoOriginalTracksExist() throws {
        let json = Data("""
        {"id": "abcdefghijk", "language": "en", "automatic_captions": {
          "en": [{"ext": "json3", "name": "English"}], "fr": [{"ext": "json3", "name": "French"}]}}
        """.utf8)
        let metadata = try MetadataDecoder.decode(json)
        #expect(metadata.automaticCaptions.map(\.key) == ["en"])
        #expect(metadata.title == "Untitled video")
    }

    @Test func rejectsLiveStreamsAndGarbage() {
        #expect(throws: YouTubeError.liveOrUpcoming) {
            try MetadataDecoder.decode(Data(#"{"id": "abcdefghijk", "live_status": "is_live"}"#.utf8))
        }
        #expect(throws: YouTubeError.self) { try MetadataDecoder.decode(Data("null".utf8)) }
    }

    @Test func selectorPrefersManualThenFallsBack() throws {
        let metadata = try MetadataDecoder.decode(Self.sample)

        #expect(CaptionTrackSelector.defaultLanguage(for: metadata, preferred: nil) == "en")
        #expect(CaptionTrackSelector.defaultLanguage(for: metadata, preferred: "es") == "es-US")
        #expect(CaptionTrackSelector.defaultLanguage(for: metadata, preferred: "zh") == "en")

        #expect(CaptionTrackSelector.track(for: metadata, languageCode: "en", preferManual: true)?.id == "manual:en")
        #expect(CaptionTrackSelector.track(for: metadata, languageCode: "en", preferManual: false)?.id == "auto:en-orig")
        #expect(CaptionTrackSelector.track(for: metadata, languageCode: "de", preferManual: false)?.id == "manual:de")
        #expect(CaptionTrackSelector.track(for: metadata, languageCode: "es-US", preferManual: true)?.id == "auto:es-US-orig")
        #expect(CaptionTrackSelector.track(for: metadata, languageCode: "it", preferManual: true) == nil)

        let english = try #require(CaptionTrackSelector.languageOptions(for: metadata).first { $0.languageCode == "en" })
        #expect(english.hasManual && english.hasAutomatic)
    }
}
