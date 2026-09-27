import Foundation

/// Talks to YouTube through yt-dlp: video info, captions, and audio for local transcription.
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
        var arguments = ["--ignore-config", "--no-playlist", "--no-warnings"]
        if let ffmpeg {
            arguments += ["--ffmpeg-location", ffmpeg.path(percentEncoded: false)]
        }
        return arguments
    }

    func fetchMetadata(for link: YouTubeLink) async throws(YouTubeError) -> VideoMetadata {
        let result = try await run(baseArguments + ["--no-progress", "--dump-single-json", "--skip-download", link.watchURL.absoluteString])
        guard result.succeeded else { throw YtDlpErrorClassifier.classify(result.standardError) }
        return try MetadataDecoder.decode(result.standardOutput)
    }

    /// Downloads `track` as json3 into `directory` and returns the file's contents.
    func downloadCaptions(_ track: CaptionTrack, for link: YouTubeLink, into directory: URL) async throws(YouTubeError) -> Data {
        let arguments = baseArguments + [
            "--no-progress",
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

    /// Downloads the best audio-only stream into `directory`, reporting progress from 0 to 1.
    func downloadAudio(
        for link: YouTubeLink,
        into directory: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws(YouTubeError) -> URL {
        let arguments = baseArguments + [
            "--format", "bestaudio/best",
            "--newline",
            "--progress-template", "download:\(Self.progressMarker) %(progress.downloaded_bytes)s %(progress.total_bytes)s %(progress.total_bytes_estimate)s",
            "--paths", directory.path(percentEncoded: false),
            "--output", "audio.%(ext)s",
            link.watchURL.absoluteString,
        ]
        let result = try await run(arguments) { line in
            if let fraction = Self.downloadProgress(from: line) { progress(fraction) }
        }
        guard result.succeeded else { throw YtDlpErrorClassifier.classify(result.standardError) }

        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        guard let audio = files.first(where: { $0.lastPathComponent.hasPrefix("audio.") && $0.pathExtension != "part" }) else {
            throw .toolFailed("yt-dlp finished without saving any audio.")
        }
        return audio
    }

    static let progressMarker = "YTTOPDF-PROGRESS"

    /// Parses a `--progress-template` line: marker, downloaded bytes, total, estimated total.
    /// yt-dlp prints `NA` for values it doesn't know.
    static func downloadProgress(from line: String) -> Double? {
        let parts = line.split(separator: " ")
        guard parts.count == 4, parts[0] == progressMarker, let downloaded = Double(parts[1]) else { return nil }
        guard let total = Double(parts[2]) ?? Double(parts[3]), total > 0 else { return nil }
        return min(1, max(0, downloaded / total))
    }

    private func run(
        _ arguments: [String],
        onOutputLine: (@Sendable (String) -> Void)? = nil
    ) async throws(YouTubeError) -> ProcessResult {
        do {
            return try await ProcessRunner.run(ytDlp, arguments: arguments, onOutputLine: onOutputLine)
        } catch {
            switch error {
            case .cancelled: throw .cancelled
            case .launchFailed(let reason): throw .toolFailed("yt-dlp couldn't be started: \(reason)")
            }
        }
    }
}
