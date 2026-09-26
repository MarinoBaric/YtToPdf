import Foundation
import Testing
@testable import YtToPdf

@Suite("Caption parsing")
struct CaptionParserTests {
    // MARK: - Fixtures (synthetic, shaped like YouTube's json3)

    /// Auto captions: word-level offsets, `\n` append events, a `[Music]` tag, a `>>` speaker
    /// change, and a cue that rolls over words from the previous one.
    private static let autoCaptions = Data("""
    {"wireMagic": "pb3", "events": [
      {"tStartMs": 0, "dDurationMs": 60000, "id": 1, "wpWinPosId": 1, "wsWinStyleId": 1},
      {"tStartMs": 500, "dDurationMs": 2000, "wWinId": 1, "segs": [{"utf8": "[Music]"}]},
      {"tStartMs": 3000, "dDurationMs": 4000, "wWinId": 1, "segs": [
        {"utf8": "so", "acAsrConf": 255}, {"utf8": " today", "tOffsetMs": 200}, {"utf8": " i'm", "tOffsetMs": 500},
        {"utf8": " going", "tOffsetMs": 700}, {"utf8": " to", "tOffsetMs": 900}, {"utf8": " show", "tOffsetMs": 1000},
        {"utf8": " you", "tOffsetMs": 1200}, {"utf8": " my", "tOffsetMs": 1350}, {"utf8": " bench", "tOffsetMs": 1500}]},
      {"tStartMs": 4600, "wWinId": 1, "aAppend": 1, "segs": [{"utf8": "\\n"}]},
      {"tStartMs": 4350, "dDurationMs": 3000, "wWinId": 1, "segs": [
        {"utf8": "my", "acAsrConf": 255}, {"utf8": " bench", "tOffsetMs": 150},
        {"utf8": " it", "tOffsetMs": 1150}, {"utf8": " took", "tOffsetMs": 1350},
        {"utf8": " three", "tOffsetMs": 1550}, {"utf8": " weeks", "tOffsetMs": 1750}]},
      {"tStartMs": 9000, "dDurationMs": 3000, "wWinId": 1, "segs": [
        {"utf8": ">>"}, {"utf8": " that", "tOffsetMs": 100}, {"utf8": " that", "tOffsetMs": 400},
        {"utf8": " looks", "tOffsetMs": 600}, {"utf8": " great", "tOffsetMs": 800}]}
    ]}
    """.utf8)

    /// Manual captions: one segment per line, punctuation, multi-line cues, `(Laughter)`.
    private static let manualCaptions = Data("""
    {"events": [
      {"tStartMs": 1000, "dDurationMs": 2000, "segs": [{"utf8": "Good evening, everyone."}]},
      {"tStartMs": 3000, "dDurationMs": 2500, "segs": [{"utf8": "Tonight I want to talk\\nabout Dr. Smith's"}]},
      {"tStartMs": 5500, "dDurationMs": 2000, "segs": [{"utf8": "remarkable workshop."}]},
      {"tStartMs": 7600, "dDurationMs": 1500, "segs": [{"utf8": "(Laughter)"}]},
      {"tStartMs": 9200, "dDurationMs": 2000, "segs": [{"utf8": "Was it worth it? Yes!"}]}
    ]}
    """.utf8)

    // MARK: - Auto captions

    @Test func autoCaptionsBecomeCleanSentences() throws {
        let transcript = try CaptionParser.parse(json3: Self.autoCaptions, languageCode: "en", source: .autoCaptions)
        let sentences = transcript.paragraphs.flatMap(\.sentences).map(\.text)

        // "my bench" is shown twice (rolling captions) but appears once; the pause after it
        // ends the first sentence.
        #expect(sentences == [
            "So today I'm going to show you my bench.",
            "It took three weeks.",
            "That that looks great.",
        ])
    }

    @Test func autoCaptionsKeepWordTimingAndMarkSpeakerChanges() throws {
        let transcript = try CaptionParser.parse(json3: Self.autoCaptions, languageCode: "en", source: .autoCaptions)

        // `>>` starts a new paragraph.
        #expect(transcript.paragraphs.count == 2)
        let words = transcript.words
        #expect(words.first?.start == 3.0)
        #expect(abs((words.first { $0.text == "three" }?.start ?? 0) - 5.9) < 0.0001)
        #expect(zip(words, words.dropFirst()).allSatisfy { $0.start <= $1.start })
        #expect(words.allSatisfy { $0.end >= $0.start })
        #expect(transcript.wordCount == 17)
    }

    // MARK: - Manual captions

    @Test func manualCaptionsSplitOnPunctuationAcrossCues() throws {
        let transcript = try CaptionParser.parse(json3: Self.manualCaptions, languageCode: "en", source: .manualCaptions)
        let sentences = transcript.paragraphs.flatMap(\.sentences).map(\.text)

        #expect(sentences == [
            "Good evening, everyone.",
            "Tonight I want to talk about Dr. Smith's remarkable workshop.",
            "Was it worth it?",
            "Yes!",
        ])
    }

    @Test func manualCaptionsSpreadWordsAcrossTheCue() throws {
        let transcript = try CaptionParser.parse(json3: Self.manualCaptions, languageCode: "en", source: .manualCaptions)
        let firstCue = Array(transcript.words.prefix(3))

        #expect(firstCue.map(\.text) == ["Good", "evening,", "everyone."])
        #expect(firstCue.first?.start == 1.0)
        #expect(abs((firstCue.last?.end ?? 0) - 3.0) < 0.0001)
        #expect(zip(firstCue, firstCue.dropFirst()).allSatisfy { abs($0.end - $1.start) < 0.0001 })
    }

    // MARK: - Failure cases

    @Test func rejectsMalformedAndEmptyFiles() {
        #expect(throws: CaptionParserError.malformed) {
            try CaptionParser.parse(json3: Data("<xml/>".utf8), languageCode: "en", source: .manualCaptions)
        }
        let onlyMusic = Data(#"{"events": [{"tStartMs": 0, "dDurationMs": 5000, "segs": [{"utf8": "[Music]"}]}]}"#.utf8)
        #expect(throws: CaptionParserError.empty) {
            try CaptionParser.parse(json3: onlyMusic, languageCode: "en", source: .autoCaptions)
        }
    }
}
