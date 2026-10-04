import Foundation
import OSLog
import SwiftData

/// Creates the SwiftData container for transcript history.
///
/// The store lives in the app's own folder: an unsandboxed app's default store is
/// `~/Library/Application Support/default.store`, a name any other app could also use.
enum HistoryContainer {
    struct Result {
        let container: ModelContainer
        /// False when the store couldn't be opened and history is kept in memory for this session.
        let isPersistent: Bool
    }

    static var storeURL: URL {
        URL.applicationSupportDirectory
            .appending(path: "YtToPdf", directoryHint: .isDirectory)
            .appending(path: "History.store", directoryHint: .notDirectory)
    }

    private static let logger = Logger(subsystem: "YtToPdf", category: "History")

    static func make(at url: URL = storeURL) -> Result {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let configuration = ModelConfiguration("History", schema: Schema([TranscriptRecord.self]), url: url)
            return Result(container: try ModelContainer(for: TranscriptRecord.self, configurations: configuration), isPersistent: true)
        } catch {
            logger.error("Opening history at \(url.path, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        }
        do {
            let memory = ModelConfiguration("History", schema: Schema([TranscriptRecord.self]), isStoredInMemoryOnly: true)
            return Result(container: try ModelContainer(for: TranscriptRecord.self, configurations: memory), isPersistent: false)
        } catch {
            // An in-memory store failing means SwiftData itself is unusable; nothing sensible remains.
            fatalError("SwiftData couldn't create an in-memory store: \(error)")
        }
    }
}
