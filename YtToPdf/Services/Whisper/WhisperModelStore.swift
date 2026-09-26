import Foundation

/// Where downloaded Whisper models live: `~/Library/Application Support/YtToPdf/Models`.
nonisolated struct WhisperModelStore: Sendable {
    static var defaultDirectory: URL {
        URL.applicationSupportDirectory
            .appending(path: "YtToPdf", directoryHint: .isDirectory)
            .appending(path: "Models", directoryHint: .isDirectory)
    }

    let directory: URL

    init(directory: URL = WhisperModelStore.defaultDirectory) {
        self.directory = directory
    }

    func url(for model: WhisperModel) -> URL {
        directory.appending(path: model.fileName, directoryHint: .notDirectory)
    }

    func isInstalled(_ model: WhisperModel) -> Bool {
        FileManager.default.fileExists(atPath: url(for: model).path(percentEncoded: false))
    }

    var installedModels: [WhisperModel] {
        WhisperModel.allCases.filter(isInstalled)
    }

    /// The installed model's file, or `.modelMissing` so the UI can offer the download.
    func installedURL(for model: WhisperModel) throws(WhisperError) -> URL {
        guard isInstalled(model) else { throw .modelMissing(model) }
        return url(for: model)
    }

    func download(
        _ model: WhisperModel,
        progress: (@Sendable (_ fraction: Double) -> Void)? = nil
    ) async throws(WhisperError) {
        let downloader = ModelDownloader(stagingDirectory: directory.appending(path: ".staging", directoryHint: .isDirectory)) { received, expected in
            let total = expected > 0 ? expected : model.approximateBytes
            progress?(min(1, Double(received) / Double(total)))
        }
        try await downloader.download(from: model.downloadURL, sha1: model.sha1, to: url(for: model))
    }

    func delete(_ model: WhisperModel) throws {
        guard isInstalled(model) else { return }
        try FileManager.default.removeItem(at: url(for: model))
    }
}
