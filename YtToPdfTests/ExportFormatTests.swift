import Foundation
import Testing
import UniformTypeIdentifiers
@testable import YtToPdf

@Suite("Text exports")
struct ExportFormatTests {
    private static func sentence(_ text: String, at start: TimeInterval, step: TimeInterval = 0.4) -> TranscriptSentence {
        TranscriptSentence(words: text.split(separator: " ").enumerated().map { index, word in
            TimedWord(text: String(word), start: start + Double(index) * step, end: start + Double(index) * step + 0.3)
        })
    }

    private static let transcript = Transcript(
        paragraphs: [
            TranscriptParagraph(sentences: [sentence("Measure the *board* twice.", at: 2), sentence("Then cut_it.", at: 5)]),
            TranscriptParagraph(sentences: [sentence("Sand [lightly] with 220 grit.", at: 40)]),
        ],
        languageCode: "en",
        source: .manualCaptions
    )

    private static let metadata = VideoMetadata(
        id: "abcdefghijk", title: "Joinery #1: Basics", channel: "Sample_Workshop", duration: 60,
        uploadDate: Date(timeIntervalSince1970: 1_710_504_000), thumbnailURL: nil,
        webpageURL: URL(string: "https://www.youtube.com/watch?v=abcdefghijk")!,
        languageCode: "en", manualCaptions: [], automaticCaptions: []
    )

    // MARK: - Markdown

    @Test func markdownHasHeaderLinksAndEscaping() {
        let markdown = MarkdownRenderer.render(Self.transcript, metadata: Self.metadata, options: TranscriptOptions())

        #expect(markdown.hasPrefix("# Joinery \\#1: Basics\n\n**Sample\\_Workshop** · Uploaded "))
        #expect(markdown.contains("[youtu.be/abcdefghijk](https://www.youtube.com/watch?v=abcdefghijk)"))
        #expect(markdown.contains("\n\n---\n\n**[\\[00:02\\]](https://www.youtube.com/watch?v=abcdefghijk&t=2s)** Measure the \\*board\\* twice. Then cut\\_it."))
        #expect(markdown.contains("\n\n**[\\[00:40\\]](https://www.youtube.com/watch?v=abcdefghijk&t=40s)** Sand \\[lightly\\] with 220 grit.\n"))
    }

    @Test func markdownWithoutHeaderOrLinks() {
        var options = TranscriptOptions()
        options.includeVideoInfo = false
        options.clickableTimestamps = false
        let markdown = MarkdownRenderer.render(Self.transcript, metadata: Self.metadata, options: options)
        #expect(markdown.hasPrefix("**\\[00:02\\]** Measure"))
        #expect(!markdown.contains("https://"))
    }

    // MARK: - SRT

    @Test func srtNumbersAndTimesCues() {
        let srt = SRTRenderer.render(Self.transcript)
        #expect(srt.hasPrefix("1\n00:00:02,000 --> 00:00:03,500\nMeasure the *board* twice.\n\n2\n00:00:05,000 --> "))
        #expect(srt.contains("3\n00:00:40,000 --> 00:00:41,900\nSand [lightly] with 220 grit.\n"))
        #expect(SRTRenderer.timestamp(3723.4567) == "01:02:03,457")
    }

    @Test func longSentencesSplitIntoReadableTwoLineCues() {
        let long = Array(repeating: "carefully", count: 30).joined(separator: " ") + "."
        let transcript = Transcript(paragraphs: [TranscriptParagraph(sentences: [Self.sentence(long, at: 0, step: 0.3)])], languageCode: "en", source: .whisper)
        let cues = SRTRenderer.cues(for: transcript)

        #expect(cues.count > 1)
        for cue in cues {
            let lines = cue.text.split(separator: "\n")
            #expect(lines.count <= 2)
            #expect(lines.allSatisfy { $0.count <= SRTRenderer.maxLineLength })
            #expect(cue.end > cue.start)
        }
        #expect(zip(cues, cues.dropFirst()).allSatisfy { $0.end <= $1.start })
    }

    @Test func shortCuesStayUpLongEnoughWithoutOverlapping() {
        let transcript = Transcript(
            paragraphs: [TranscriptParagraph(sentences: [Self.sentence("Yes.", at: 1), Self.sentence("No.", at: 1.5), Self.sentence("Maybe.", at: 10)])],
            languageCode: "en", source: .manualCaptions
        )
        let cues = SRTRenderer.cues(for: transcript)
        #expect(cues[0].end < cues[1].start, "a short cue can't run into the next one")
        #expect(cues[2].end - cues[2].start >= SRTRenderer.minCueDuration)
    }

    // MARK: - Formats

    @Test func formatsRouteToTheirRenderers() {
        let options = TranscriptOptions()
        #expect(ExportFormat.pdf.text(for: Self.transcript, metadata: Self.metadata, options: options) == nil)
        #expect(ExportFormat.plainText.text(for: Self.transcript, metadata: Self.metadata, options: options)?.hasPrefix("Joinery #1: Basics\n") == true)
        #expect(ExportFormat.markdown.contentType.preferredFilenameExtension == "md")
        #expect(ExportFormat.subtitles.contentType.preferredFilenameExtension == "srt")
    }
}
