import Foundation
import Synchronization
import Testing
@testable import YtToPdf

@Suite("Whisper model storage and download")
struct ModelStoreTests {
    private let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "ModelStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    private func makeSource(bytes: Int = 300_000) throws -> URL {
        let source = root.appending(path: "source.bin")
        try Data((0..<bytes).map { UInt8($0 % 251) }).write(to: source)
        return source
    }

    @Test func catalogueMatchesUpstreamFileNames() {
        #expect(WhisperModel.default == .base)
        #expect(WhisperModel.allCases.map(\.fileName) == ["ggml-base.bin", "ggml-small.bin", "ggml-medium.bin"])
        #expect(WhisperModel.base.downloadURL.absoluteString == "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin")
        #expect(WhisperModel.allCases.allSatisfy { $0.sha1.count == 40 })
    }

    @Test func reportsMissingModelsAndDeletes() throws {
        let store = WhisperModelStore(directory: root)
        #expect(store.installedModels.isEmpty)
        #expect(throws: WhisperError.modelMissing(.small)) { try store.installedURL(for: .small) }

        try Data("model".utf8).write(to: store.url(for: .small))
        #expect(store.installedModels == [.small])
        #expect(try store.installedURL(for: .small).lastPathComponent == "ggml-small.bin")

        try store.delete(.small)
        #expect(!store.isInstalled(.small))
    }

    @Test func downloadVerifiesChecksumAndReportsProgress() async throws {
        let source = try makeSource()
        let sha1 = try ModelDownloader.sha1(of: source)
        let destination = root.appending(path: "Models/ggml-test.bin")
        let lastProgress = Mutex<Int64>(0)

        let downloader = ModelDownloader(stagingDirectory: root.appending(path: "staging")) { received, _ in
            lastProgress.withLock { $0 = received }
        }
        try await downloader.download(from: source, sha1: sha1, to: destination)

        #expect(try Data(contentsOf: destination) == Data(contentsOf: source))
        #expect(lastProgress.withLock { $0 } == 300_000)
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: root.appending(path: "staging").path)) ?? []
        #expect(leftovers.isEmpty, "staged download should be cleaned up")
    }

    @Test func checksumMismatchLeavesNothingBehind() async throws {
        let source = try makeSource()
        let destination = root.appending(path: "Models/ggml-test.bin")
        let downloader = ModelDownloader(stagingDirectory: root.appending(path: "staging"))

        await #expect(throws: WhisperError.modelChecksumMismatch) {
            try await downloader.download(from: source, sha1: String(repeating: "0", count: 40), to: destination)
        }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }

    @Test func missingSourceFailsCleanly() async {
        let downloader = ModelDownloader(stagingDirectory: root.appending(path: "staging"))
        await #expect(throws: WhisperError.self) {
            try await downloader.download(from: root.appending(path: "nope.bin"), sha1: "", to: root.appending(path: "out.bin"))
        }
    }
}
