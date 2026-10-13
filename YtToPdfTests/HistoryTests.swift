import Foundation
import SwiftData
import Testing
@testable import YtToPdf

@MainActor
@Suite("History")
struct HistoryTests {
    private let container: ModelContainer
    private let store: HistoryStore

    init() throws {
        container = try ModelContainer(for: TranscriptRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        store = HistoryStore(context: container.mainContext)
    }

    private static func transcript(_ text: String, language: String = "en", source: TranscriptSource = .manualCaptions) -> Transcript {
        let words = text.split(separator: " ").enumerated().map { index, word in
            TimedWord(text: String(word), start: Double(index), end: Double(index) + 0.5)
        }
        return Transcript(paragraphs: [TranscriptParagraph(sentences: [TranscriptSentence(words: words)])], languageCode: language, source: source)
    }

    private static func metadata(id: String = "abcdefghijk", title: String = "Joinery Basics") -> VideoMetadata {
        VideoMetadata(
            id: id, title: title, channel: "Sample Workshop", duration: 300, uploadDate: nil,
            thumbnailURL: URL(string: "https://i.ytimg.com/vi/\(id)/hq.jpg"),
            webpageURL: URL(string: "https://www.youtube.com/watch?v=\(id)")!,
            languageCode: "en",
            manualCaptions: [CaptionTrack(key: "en", languageCode: "en", name: "English", isAutomatic: false)],
            automaticCaptions: []
        )
    }

    private func allRecords() throws -> [TranscriptRecord] {
        try container.mainContext.fetch(FetchDescriptor<TranscriptRecord>())
    }

    // MARK: - Store

    @Test func savesEverythingNeededToReopen() throws {
        var options = TranscriptOptions()
        options.timestampMode = .every30
        let record = try store.save(metadata: Self.metadata(), transcript: Self.transcript("Glue the joint."), thumbnail: Data([1, 2, 3]), options: options)

        #expect(record.decodedMetadata() == Self.metadata())
        #expect(try record.decodedTranscript() == Self.transcript("Glue the joint."))
        #expect(record.decodedOptions() == options)
        #expect(record.thumbnailData == Data([1, 2, 3]))
        #expect(record.wordCount == 3)
        #expect(record.plainText == "Glue the joint.")
    }

    @Test func regeneratingTheSameVideoAndLanguageReplacesTheEntry() throws {
        try store.save(metadata: Self.metadata(), transcript: Self.transcript("First try."), thumbnail: Data([9]), options: .init())
        try store.save(metadata: Self.metadata(), transcript: Self.transcript("Second, better try."), thumbnail: nil, options: .init())
        try store.save(metadata: Self.metadata(), transcript: Self.transcript("Prvi pokušaj.", language: "hr"), thumbnail: nil, options: .init())
        try store.save(metadata: Self.metadata(id: "zyxwvutsrqp"), transcript: Self.transcript("Other video."), thumbnail: nil, options: .init())

        let records = try allRecords()
        #expect(records.count == 3)
        let english = try #require(records.first { $0.videoID == "abcdefghijk" && $0.languageCode == "en" })
        #expect(english.plainText == "Second, better try.")
        #expect(english.thumbnailData == Data([9]), "a missing thumbnail on regenerate keeps the old one")
    }

    @Test func updatesOptionsAndDeletes() throws {
        let record = try store.save(metadata: Self.metadata(), transcript: Self.transcript("Hello."), thumbnail: nil, options: .init())
        var options = TranscriptOptions()
        options.timestampStyle = .hoursMinutesSeconds
        store.updateOptions(options, for: record)
        #expect(record.decodedOptions()?.timestampStyle == .hoursMinutesSeconds)
        #expect(store.record(for: record.persistentModelID) === record)

        store.delete(record)
        #expect(try allRecords().isEmpty)
    }

    @Test func undoAndRedoOfADeleteAreWrittenToDisk() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "HistoryUndo-\(UUID().uuidString)/History.store")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let created = Date(timeIntervalSince1970: 1_760_000_000)
        func countOnDisk() throws -> [TranscriptRecord] {
            try ModelContext(HistoryContainer.make(at: url).container).fetch(FetchDescriptor<TranscriptRecord>())
        }

        let history = HistoryContainer.make(at: url)
        let undo = UndoManager()
        // No run loop in tests, so group explicitly the way the app's event loop would.
        undo.groupsByEvent = false
        let store = HistoryStore(context: history.container.mainContext)
        store.undoManager = undo

        let record = try store.save(metadata: Self.metadata(), transcript: Self.transcript("Undo me."), thumbnail: Data([4]), options: .init())
        record.createdAt = created

        undo.beginUndoGrouping()
        store.delete(record)
        undo.endUndoGrouping()
        #expect(undo.undoActionName == "Delete Transcript")
        #expect(try countOnDisk().isEmpty)

        undo.undo()
        let restored = try countOnDisk()
        #expect(restored.map(\.plainText) == ["Undo me."])
        #expect(restored.first?.createdAt == created, "restored entries keep their place in history")
        #expect(restored.first?.thumbnailData == Data([4]))
        #expect(undo.canRedo)

        undo.redo()
        #expect(try countOnDisk().isEmpty)
    }

    @Test func oldRecordsWithoutStoredMetadataStillOpen() throws {
        let record = try store.save(metadata: Self.metadata(), transcript: Self.transcript("Hello."), thumbnail: nil, options: .init())
        record.metadataData = Data()
        record.optionsData = nil
        let rebuilt = record.decodedMetadata()
        #expect(rebuilt.id == "abcdefghijk")
        #expect(rebuilt.title == "Joinery Basics")
        #expect(record.decodedOptions() == nil)
    }

    @Test func historySurvivesReopeningTheStoreOnDisk() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "HistoryTests-\(UUID().uuidString)/History.store")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        do {
            let first = HistoryContainer.make(at: url)
            #expect(first.isPersistent)
            try HistoryStore(context: first.container.mainContext)
                .save(metadata: Self.metadata(), transcript: Self.transcript("Kept on disk."), thumbnail: nil, options: .init())
        }

        let reopened = HistoryContainer.make(at: url)
        let records = try reopened.container.mainContext.fetch(FetchDescriptor<TranscriptRecord>())
        #expect(records.map(\.plainText) == ["Kept on disk."])
        #expect(HistoryContainer.storeURL.path.hasSuffix("Application Support/YtToPdf/History.store"))
    }

    // MARK: - Reopening

    @Test func reopeningShowsTheTranscriptWithoutFetching() throws {
        var options = TranscriptOptions()
        options.timestampMode = .off
        let record = try store.save(metadata: Self.metadata(), transcript: Self.transcript("Saved words here."), thumbnail: Data([7]), options: options)

        // No tools at all: any attempt to reach YouTube would surface an error.
        let model = GenerateViewModel(inventory: .empty, options: TranscriptOptions())
        model.history = store
        model.open(record)

        #expect(model.transcript?.plainText == "Saved words here.")
        #expect(model.metadata?.id == "abcdefghijk")
        #expect(model.thumbnailData == Data([7]))
        #expect(model.urlText == "https://www.youtube.com/watch?v=abcdefghijk")
        #expect(model.options.timestampMode == .off)
        #expect(model.currentRecordID == record.persistentModelID)
        #expect(model.activity == .idle)
        #expect(model.error == nil)
        #expect(model.fingerprint?.sliceCount == SpeechFingerprint.defaultSliceCount)
        #expect(model.fingerprint?.variation == FingerprintVariation(seed: FingerprintSeed.value(for: "abcdefghijk")))

        model.reset()
        #expect(model.fingerprint == nil)
    }

    @Test func changingOptionsOnAReopenedTranscriptIsRemembered() throws {
        let record = try store.save(metadata: Self.metadata(), transcript: Self.transcript("Hi."), thumbnail: nil, options: .init())
        let model = GenerateViewModel(inventory: .empty, options: TranscriptOptions())
        model.history = store
        model.open(record)

        model.options.timestampMode = .every60
        #expect(record.decodedOptions()?.timestampMode == .every60)

        model.recordWillBeDeleted(record)
        #expect(model.transcript == nil)
        #expect(model.currentRecordID == nil)
        #expect(model.urlText.isEmpty)
    }

    // MARK: - Sidebar helpers

    @Test func groupsByRecency() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: 15)))
        func daysAgo(_ days: Int) -> Date { now.addingTimeInterval(-Double(days) * 86_400) }

        #expect(HistoryGroup.bucket(for: daysAgo(0), now: now, calendar: calendar) == "Today")
        #expect(HistoryGroup.bucket(for: daysAgo(1), now: now, calendar: calendar) == "Yesterday")
        #expect(HistoryGroup.bucket(for: daysAgo(5), now: now, calendar: calendar) == "Previous 7 Days")
        #expect(HistoryGroup.bucket(for: daysAgo(40), now: now, calendar: calendar) == daysAgo(40).formatted(.dateTime.month(.wide).year()))
    }

    @Test func snippetsShowContextAroundTheMatch() {
        let text = "First we measure the board twice, then we cut it with a sharp saw and sand the edges smooth before gluing."
        let snippet = SearchSnippet.make(from: text, around: "SHARP", radius: 20)
        #expect(snippet == "…we cut it with a sharp saw and sand the…")
        #expect(SearchSnippet.make(from: "Short text.", around: "short") == "Short text.")
        #expect(SearchSnippet.make(from: text, around: "missing") == nil)
    }
}
