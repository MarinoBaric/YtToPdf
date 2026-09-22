import Foundation
import Testing
@testable import YtToPdf

@Suite("ToolLocator")
struct ToolLocatorTests {
    private let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "ToolLocatorTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    private func makeDirectory(_ name: String) throws -> URL {
        let url = root.appending(path: name, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeExecutable(_ name: String, in directory: URL, executable: Bool = true) throws {
        let url = directory.appending(path: name)
        try Data("#!/bin/sh\n".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: executable ? 0o755 : 0o644], ofItemAtPath: url.path)
    }

    @Test func findsAllToolsAndReportsComplete() throws {
        let bin = try makeDirectory("bin")
        for name in ["yt-dlp", "ffmpeg", "whisper-cli", "brew"] {
            try makeExecutable(name, in: bin)
        }

        let inventory = ToolLocator(searchDirectories: [bin]).scan()

        #expect(inventory.isComplete)
        #expect(inventory.installCommand == nil)
        #expect(inventory.homebrewURL?.lastPathComponent == "brew")
        #expect(try inventory.url(for: .whisper).lastPathComponent == "whisper-cli")
    }

    @Test func installCommandListsOnlyMissingFormulas() throws {
        let bin = try makeDirectory("bin")
        try makeExecutable("ffmpeg", in: bin)

        let inventory = ToolLocator(searchDirectories: [bin]).scan()

        #expect(inventory.missingTools == [.ytDlp, .whisper])
        #expect(inventory.installCommand == "brew install yt-dlp whisper-cpp")
        #expect(inventory.homebrewURL == nil)
        #expect(throws: ToolError.missing(.ytDlp)) { try inventory.url(for: .ytDlp) }
    }

    @Test func prefersEarlierDirectoryAndFallsBackToLegacyWhisperName() throws {
        let homebrew = try makeDirectory("opt-homebrew-bin")
        let local = try makeDirectory("usr-local-bin")
        try makeExecutable("yt-dlp", in: homebrew)
        try makeExecutable("yt-dlp", in: local)
        try makeExecutable("whisper-cpp", in: local)

        let locator = ToolLocator(searchDirectories: [homebrew, local])

        #expect(locator.locate(.ytDlp)?.deletingLastPathComponent().lastPathComponent == "opt-homebrew-bin")
        #expect(locator.locate(.whisper)?.lastPathComponent == "whisper-cpp")
    }

    @Test func ignoresFilesThatAreNotExecutable() throws {
        let bin = try makeDirectory("bin")
        try makeExecutable("yt-dlp", in: bin, executable: false)

        #expect(ToolLocator(searchDirectories: [bin]).locate(.ytDlp) == nil)
    }
}
