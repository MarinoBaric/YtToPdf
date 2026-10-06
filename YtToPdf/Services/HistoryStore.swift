import Foundation
import OSLog
import SwiftData

/// Saves, updates and deletes transcripts in the SwiftData history.
final class HistoryStore {
    private let context: ModelContext
    private let logger = Logger(subsystem: "YtToPdf", category: "History")
    /// The window's undo manager, so Edit › Undo can bring back a deleted transcript.
    weak var undoManager: UndoManager?

    init(context: ModelContext) {
        self.context = context
    }

    /// Saves a transcript. Generating the same video in the same language again replaces the
    /// earlier entry instead of piling up duplicates.
    @discardableResult
    func save(metadata: VideoMetadata, transcript: Transcript, thumbnail: Data?, options: TranscriptOptions) throws -> TranscriptRecord {
        let record: TranscriptRecord
        if let existing = try existingRecord(videoID: metadata.id, languageCode: transcript.languageCode) {
            try existing.update(metadata: metadata, transcript: transcript, thumbnailData: thumbnail, options: options)
            record = existing
        } else {
            record = try TranscriptRecord(metadata: metadata, transcript: transcript, thumbnailData: thumbnail, options: options)
            context.insert(record)
        }
        try context.save()
        return record
    }

    func updateOptions(_ options: TranscriptOptions, for record: TranscriptRecord) {
        guard let data = try? JSONEncoder().encode(options), data != record.optionsData else { return }
        record.optionsData = data
        persist()
    }

    /// Deletes a transcript and registers an undo that restores it.
    ///
    /// SwiftData's own undo can't bring back a deletion that has already been saved (the
    /// restored object vanishes on the next save), so undo re-creates the entry from a snapshot.
    func delete(_ record: TranscriptRecord) {
        let snapshot = Snapshot(record)
        context.delete(record)
        persist()

        guard let undoManager, let snapshot else { return }
        undoManager.registerUndo(withTarget: self) { store in
            guard let restored = store.restore(snapshot) else { return }
            // Registering during undo makes this the redo action.
            store.undoManager?.registerUndo(withTarget: store) { $0.delete(restored) }
            store.undoManager?.setActionName("Delete Transcript")
        }
        undoManager.setActionName("Delete Transcript")
    }

    private func restore(_ snapshot: Snapshot) -> TranscriptRecord? {
        do {
            let record = try TranscriptRecord(
                metadata: snapshot.metadata,
                transcript: snapshot.transcript,
                thumbnailData: snapshot.thumbnail,
                options: snapshot.options,
                createdAt: snapshot.createdAt
            )
            context.insert(record)
            try context.save()
            return record
        } catch {
            logger.error("Restoring a deleted transcript failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Everything needed to re-create a deleted entry exactly as it was.
    private struct Snapshot {
        let metadata: VideoMetadata
        let transcript: Transcript
        let thumbnail: Data?
        let options: TranscriptOptions
        let createdAt: Date

        init?(_ record: TranscriptRecord) {
            guard let transcript = try? record.decodedTranscript() else { return nil }
            metadata = record.decodedMetadata()
            self.transcript = transcript
            thumbnail = record.thumbnailData
            options = record.decodedOptions() ?? TranscriptOptions()
            createdAt = record.createdAt
        }
    }

    func record(for id: PersistentIdentifier) -> TranscriptRecord? {
        context.model(for: id) as? TranscriptRecord
    }

    private func existingRecord(videoID: String, languageCode: String) throws -> TranscriptRecord? {
        var descriptor = FetchDescriptor<TranscriptRecord>(
            predicate: #Predicate { $0.videoID == videoID && $0.languageCode == languageCode }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func persist() {
        do {
            try context.save()
        } catch {
            logger.error("Saving history failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
