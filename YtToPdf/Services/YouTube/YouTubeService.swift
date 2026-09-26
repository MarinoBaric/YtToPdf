import Foundation

/// Talks to YouTube through yt-dlp: video info and caption downloads.
nonisolated struct YouTubeService: Sendable {
    let ytDlp: URL
    let ffmpeg: URL?

    init(ytDlp: URL, ffmpeg: URL? = nil) {
        self.ytDlp = ytDlp
        self.ffmpeg = ffmpeg
    }

    init(inventory: ToolInventory) throws(ToolError) {
        self.init(ytDlp: try inventory.url(for: .ytDlp), ffmpeg: inventory.locations[.ffmpeg])
    }

    /// Arguments shared by every call, so a user's yt-dlp config can't change behaviour.
    private var baseArguments: [String] {
        var arguments = ["--ignore-config", "--no-playlist", "--no-warnings", "--no-progress"]
        if let ffmpeg {
            arguments += ["--ffmpeg-location", ffmpeg.path(percentEncoded: false)]
        }
        return arguments
    }

    func fetchMetadata(for link: YouTubeLink) async throws(YouTubeError) -> VideoMetadata {
        let result = try await run(baseArguments + ["--dump-single-json", "--skip-download", link.watchURL.absoluteString])
        guard result.succeeded else { throw YtDlpErrorClassifier.classify(result.standardError) }
        return try MetadataDecoder.decode(result.standardOutput)
    }

    /// Downloads `track` as json3 into `directory` and returns the file's contents.
    func downloadCaptions(_ track: CaptionTrack, for link: YouTubeLink, into directory: URL) async throws(YouTubeError) -> Data {
        let arguments = baseArguments + [
            "--skip-download",
            track.isAutomatic ? "--write-auto-subs" : "--write-subs",
            "--sub-langs", NSRegularExpression.escapedPattern(for: track.key),
            "--sub-format", "json3",
            "--paths", directory.path(percentEncoded: false),
            "--output", "captions.%(ext)s",
            link.watchURL.absoluteString,
        ]
        let result = try await run(arguments)
        guard result.succeeded else { throw YtDlpErrorClassifier.classify(result.standardError) }

        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        guard let file = files.first(where: { $0.pathExtension == "json3" }),
              let data = try? Data(contentsOf: file), !data.isEmpty
        else { throw .captionsUnavailable }
        return data
    }

    private func run(_ arguments: [String]) async throws(YouTubeError) -> ProcessResult {
        do {
            return try await ProcessRunner.run(ytDlp, arguments: arguments)
        } catch {
            switch error {
            case .cancelled: throw .cancelled
            case .launchFailed(let reason): throw .toolFailed("yt-dlp couldn't be started: \(reason)")
            }
        }
    }
}
