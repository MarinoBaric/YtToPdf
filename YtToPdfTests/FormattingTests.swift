import Foundation
import Testing
@testable import YtToPdf

@Suite("Formatting and layout")
struct FormattingTests {
    /// Two paragraphs; sentences start at 0, 10, 20, 35, 50 / 62, 70, 95 seconds.
    private static let transcript: Transcript = {
        func sentence(_ text: String, at start: TimeInterval) -> TranscriptSentence {
            let words = text.split(separator: " ").enumerated().map { index, word in
                TimedWord(text: String(word), start: start + Double(index) * 0.5, end: start + Double(index) * 0.5 + 0.4)
            }
            return TranscriptSentence(words: words)
        }
        return Transcript(
            paragraphs: [
                TranscriptParagraph(sentences: [
                    sentence("One two.", at: 0), sentence("Three four.", at: 10), sentence("Five six.", at: 20),
                    sentence("Seven eight.", at: 35), sentence("Nine ten.", at: 50),
                ]),
                TranscriptParagraph(sentences: [
                    sentence("Eleven twelve.", at: 62), sentence("Thirteen.", at: 70), sentence("Fourteen fifteen.", at: 95),
                ]),
            ],
            languageCode: "en",
            source: .manualCaptions
        )
    }()

    private static let metadata = VideoMetadata(
        id: "abcdefghijk", title: "Sample Talk", channel: "Sample Channel", duration: 100,
        uploadDate: Date(timeIntervalSince1970: 1_710_504_000), thumbnailURL: nil,
        webpageURL: URL(string: "https://www.youtube.com/watch?v=abcdefghijk")!,
        languageCode: "en", manualCaptions: [], automaticCaptions: []
    )

    // MARK: - Time formatting

    @Test(arguments: [
        (0.0, TranscriptOptions.TimestampStyle.minutesSeconds, "[00:00]"),
        (65.9, .minutesSeconds, "[01:05]"),
        (4512, .minutesSeconds, "[75:12]"),
        (65, .hoursMinutesSeconds, "[00:01:05]"),
        (4512, .hoursMinutesSeconds, "[01:15:12]"),
        (-3, .minutesSeconds, "[00:00]"),
    ])
    func formatsTimestamps(_ seconds: TimeInterval, _ style: TranscriptOptions.TimestampStyle, _ expected: String) {
        #expect(TimeFormatting.timestamp(seconds, style: style) == expected)
    }

    @Test func formatsDurations() {
        #expect(TimeFormatting.duration(245) == "4:05")
        #expect(TimeFormatting.duration(754) == "12:34")
        #expect(TimeFormatting.duration(3723) == "1:02:03")
        #expect(TimeFormatting.timestamp(65, style: .minutesSeconds, brackets: false) == "01:05")
    }

    // MARK: - Layout

    @Test func offAndPerParagraphKeepParagraphsWhole() {
        let off = TranscriptLayout.blocks(for: Self.transcript, mode: .off)
        #expect(off.count == 2)
        #expect(off.allSatisfy { $0.timestamp == nil && $0.startsParagraph })

        let perParagraph = TranscriptLayout.blocks(for: Self.transcript, mode: .perParagraph)
        #expect(perParagraph.map(\.timestamp) == [0, 62])
    }

    @Test func intervalsSplitAtTheFirstSentenceInEachWindow() {
        let blocks = TranscriptLayout.blocks(for: Self.transcript, mode: .every30)
        // Windows: 0–30 (0), 30–60 (35), 60–90 (62), 90–120 (95).
        #expect(blocks.map(\.timestamp) == [0, 35, 62, 95])
        #expect(blocks.map(\.startsParagraph) == [true, false, true, false])
        #expect(blocks.map(\.text) == ["One two. Three four. Five six.", "Seven eight. Nine ten.", "Eleven twelve. Thirteen.", "Fourteen fifteen."])
        #expect(blocks.map(\.id) == [0, 1, 2, 3])
    }

    @Test func intervalLongerThanAParagraphLeavesLaterParagraphsUnstamped() {
        let blocks = TranscriptLayout.blocks(for: Self.transcript, mode: .every60)
        // 62 s falls in the second minute, so paragraph two is stamped; nothing else is.
        #expect(blocks.map(\.timestamp) == [0, 62])
        let fine = TranscriptLayout.blocks(for: Self.transcript, mode: .every15)
        #expect(fine.compactMap(\.timestamp) == [0, 20, 35, 50, 62, 95])
        #expect(fine.map(\.text).joined(separator: " ") == Self.transcript.paragraphs.map(\.text).joined(separator: " "))
    }

    // MARK: - Plain text

    @Test func plainTextWithHeaderAndTimestamps() {
        var options = TranscriptOptions()
        options.timestampMode = .every30
        let text = PlainTextRenderer.render(Self.transcript, metadata: Self.metadata, options: options)

        #expect(text.hasPrefix("Sample Talk\nSample Channel · "))
        #expect(text.contains("1:40 · 15 words\nhttps://www.youtube.com/watch?v=abcdefghijk\n\n[00:00] One two."))
        #expect(text.contains("Five six.\n[00:35] Seven eight."), "an interval split is a line break")
        #expect(text.contains("Nine ten.\n\n[01:02] Eleven"), "a paragraph break is a blank line")
        #expect(text.hasSuffix("[01:35] Fourteen fifteen.\n"))
    }

    @Test func plainTextWithoutHeaderOrTimestamps() {
        var options = TranscriptOptions()
        options.timestampMode = .off
        options.includeVideoInfo = false
        let text = PlainTextRenderer.render(Self.transcript, metadata: Self.metadata, options: options)
        #expect(text == "One two. Three four. Five six. Seven eight. Nine ten.\n\nEleven twelve. Thirteen. Fourteen fifteen.\n")
    }

    // MARK: - Search

    @Test func searchIgnoresCaseAndAccents() {
        let text = "Café culture: the CAFE on the corner, café-style."
        #expect(TextSearch.ranges(of: "cafe", in: text).map { String(text[$0]) } == ["Café", "CAFE", "café"])
        #expect(TextSearch.ranges(of: "  ", in: text).isEmpty)
        #expect(TextSearch.ranges(of: "aa", in: "aaaa").count == 2, "matches don't overlap")
    }

    // MARK: - Options and plan

    @Test func defaultOptionsRoundTrip() throws {
        let defaults = try #require(UserDefaults(suiteName: "FormattingTests-\(UUID().uuidString)"))
        #expect(DefaultOptions.load(from: defaults) == TranscriptOptions())

        var options = TranscriptOptions()
        options.timestampMode = .every15
        options.timestampStyle = .hoursMinutesSeconds
        options.whisperModel = .small
        DefaultOptions.save(options, to: defaults)
        #expect(DefaultOptions.load(from: defaults) == options)
    }

    @Test func planShowsWhisperStepsOnlyWithoutCaptions() {
        var metadata = Self.metadata
        #expect(GenerationPlan.steps(for: metadata, languageCode: nil, preferManual: true) == GenerationPlan.whisperSteps)

        metadata.automaticCaptions = [CaptionTrack(key: "en-orig", languageCode: "en", name: "English", isAutomatic: true)]
        #expect(GenerationPlan.steps(for: metadata, languageCode: nil, preferManual: true) == GenerationPlan.captionSteps)
        #expect(GenerationPlan.steps(for: metadata, languageCode: "de", preferManual: true) == GenerationPlan.whisperSteps)
    }
}
