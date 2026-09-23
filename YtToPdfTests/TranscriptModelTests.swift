import Foundation
import SwiftData
import Testing
@testable import YtToPdf

@MainActor
@Suite("Transcript models")
struct TranscriptModelTests {
    private let transcript = Transcript(
        paragraphs: [
            TranscriptParagraph(sentences: [
                TranscriptSentence(words: [
                    TimedWord(text: "Hello", start: 0, end: 0.4),
                    TimedWord(text: "world.", start: 0.4, end: 0.9),
                ]),
            ]),
            TranscriptParagraph(sentences: [
                TranscriptSentence(words: [
                    TimedWord(text: "Second", start: 5, end: 5.3),
                    TimedWord(text: "paragraph.", start: 5.3, end: 6),
                ]),
            ]),
        ],
        languageCode: "en",
        source: .manualCaptions
    )

    private let metadata = VideoMetadata(
        id: "dQw4w9WgXcQ",
        title: "Test video",
        channel: "Test channel",
        duration: 6,
        uploadDate: nil,
        thumbnailURL: nil,
        webpageURL: URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ")!,
        manualCaptions: [],
        automaticCaptions: []
    )

    @Test func derivedTextAndTiming() {
        #expect(transcript.wordCount == 4)
        #expect(transcript.plainText == "Hello world.\n\nSecond paragraph.")
        #expect(transcript.paragraphs[1].start == 5)
        #expect(transcript.paragraphs[1].end == 6)
    }

    @Test func recordPersistsAndRestoresTranscript() throws {
        let container = try ModelContainer(
            for: TranscriptRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        context.insert(try TranscriptRecord(metadata: metadata, transcript: transcript, thumbnailData: nil))
        try context.save()

        let records = try context.fetch(FetchDescriptor<TranscriptRecord>())
        let record = try #require(records.first)
        #expect(record.wordCount == 4)
        #expect(record.source == .manualCaptions)
        #expect(try record.decodedTranscript() == transcript)
    }
}
