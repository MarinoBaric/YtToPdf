import CryptoKit
import Foundation
import Synchronization

/// Downloads one large file with byte-level progress, verifies its SHA-1, then moves it into place.
nonisolated final class ModelDownloader: NSObject, URLSessionDownloadDelegate, Sendable {
    typealias Progress = @Sendable (_ received: Int64, _ expected: Int64) -> Void

    private struct State {
        var continuation: CheckedContinuation<URL, any Error>?
        var stagedFile: URL?
    }

    private let progress: Progress?
    private let stagingDirectory: URL
    private let state = Mutex(State())

    init(stagingDirectory: URL, progress: Progress? = nil) {
        self.stagingDirectory = stagingDirectory
        self.progress = progress
    }

    /// Downloads `source` to `destination`, replacing it only after the checksum matches.
    @concurrent
    func download(from source: URL, sha1 expected: String, to destination: URL) async throws(WhisperError) {
        let session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        let staged: URL
        do {
            let task = session.downloadTask(with: source)
            staged = try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    state.withLock { $0.continuation = continuation }
                    task.resume()
                }
            } onCancel: {
                task.cancel()
            }
        } catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled { throw .cancelled }
            throw .modelDownloadFailed(error.localizedDescription)
        }
        defer { try? FileManager.default.removeItem(at: staged) }

        guard (try? Self.sha1(of: staged)) == expected.lowercased() else {
            throw .modelChecksumMismatch
        }
        do {
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: staged)
        } catch {
            throw .modelDownloadFailed("The model couldn't be saved: \(error.localizedDescription)")
        }
    }

    static func sha1(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = Insecure.SHA1()
        while let chunk = try handle.read(upToCount: 4 * 1024 * 1024), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - URLSessionDownloadDelegate

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData _: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        progress?(totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // The system deletes `location` when this returns, so move it now.
        if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            finish(.failure(URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "The server responded with error \(http.statusCode)."])))
            return
        }
        do {
            try FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
            let staged = stagingDirectory.appending(path: UUID().uuidString + ".download")
            try FileManager.default.moveItem(at: location, to: staged)
            state.withLock { $0.stagedFile = staged }
        } catch {
            finish(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        if let error {
            finish(.failure(error))
        } else if let staged = state.withLock({ $0.stagedFile }) {
            finish(.success(staged))
        } else {
            finish(.failure(URLError(.cannotCreateFile)))
        }
    }

    private func finish(_ result: Result<URL, any Error>) {
        let continuation = state.withLock { state in
            defer { state.continuation = nil }
            return state.continuation
        }
        continuation?.resume(with: result)
    }
}
