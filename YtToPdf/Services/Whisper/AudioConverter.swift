import Foundation

/// Converts downloaded audio into the 16 kHz mono 16-bit WAV that whisper.cpp expects.
nonisolated struct AudioConverter: Sendable {
    let ffmpeg: URL

    func convertToWhisperWAV(
        _ input: URL,
        output: URL,
        duration: TimeInterval,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws(WhisperError) {
        let arguments = [
            "-nostdin", "-hide_banner", "-loglevel", "error", "-y",
            "-i", input.path(percentEncoded: false),
            "-vn", "-ac", "1", "-ar", "16000", "-c:a", "pcm_s16le",
            "-progress", "pipe:1", "-nostats",
            output.path(percentEncoded: false),
        ]

        let result: ProcessResult
        do {
            result = try await ProcessRunner.run(ffmpeg, arguments: arguments) { line in
                if let fraction = Self.progress(from: line, duration: duration) { progress(fraction) }
            }
        } catch {
            switch error {
            case .cancelled: throw .cancelled
            case .launchFailed(let reason): throw .audioConversionFailed("FFmpeg couldn't be started: \(reason)")
            }
        }

        guard result.succeeded, FileManager.default.fileExists(atPath: output.path(percentEncoded: false)) else {
            let detail = result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
            throw .audioConversionFailed(detail.isEmpty ? "FFmpeg exited with code \(result.exitCode)." : detail)
        }
    }

    /// Parses ffmpeg's `-progress` key=value output (`out_time_us=12345678`).
    static func progress(from line: String, duration: TimeInterval) -> Double? {
        guard duration > 0, line.hasPrefix("out_time_us="),
              let microseconds = Double(line.dropFirst("out_time_us=".count))
        else { return nil }
        return min(1, max(0, microseconds / 1_000_000 / duration))
    }
}
