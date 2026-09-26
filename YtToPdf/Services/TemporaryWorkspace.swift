import Foundation

/// A scratch directory for one job's downloads, removed when the job ends.
nonisolated enum TemporaryWorkspace {
    static var root: URL {
        FileManager.default.temporaryDirectory.appending(path: "YtToPdf", directoryHint: .isDirectory)
    }

    /// Runs `body` with a fresh directory and deletes it afterwards, whether `body` succeeds,
    /// throws or is cancelled.
    static func withDirectory<T, E: Error>(
        _ body: (URL) async throws(E) -> T
    ) async throws(E) -> T {
        let directory = root.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        return try await body(directory)
    }

    /// Removes leftovers from jobs that were interrupted by a crash or force quit.
    static func removeStaleDirectories() {
        try? FileManager.default.removeItem(at: root)
    }
}
