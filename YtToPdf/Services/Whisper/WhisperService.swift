import Foundation

/// Transcribes a 16 kHz WAV file locally with whisper-cli.
nonisolated struct WhisperService: Sendable {
    let whisperCLI: URL

    /// - Parameter language: An ISO 639-1 code such as `en` or `hr`, or `nil` to auto-detect.
    func transcribe(
        _ wav: URL,
        model: URL,
        language: String?,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws(WhisperError) -> WhisperOutputParser.Output {
        let outputBase = wav.deletingPathExtension().appendingPathExtension("whisper")
        let languageArgument = language.map(CaptionTrack.baseLanguage(of:)) ?? "auto"

        var result = try await run(wav: wav, model: model, language: languageArgument, outputBase: outputBase, progress: progress)
        if !result.succeeded, languageArgument != "auto", result.standardError.lowercased().contains("unknown language") {
            // YouTube's language code isn't one Whisper knows; let it detect instead.
            result = try await run(wav: wav, model: model, language: "auto", outputBase: outputBase, progress: progress)
        }
        guard result.succeeded else {
            throw .transcriptionFailed(Self.lastMeaningfulLine(of: result.standardError) ?? "whisper.cpp exited with code \(result.exitCode).")
        }

        let jsonURL = outputBase.appendingPathExtension("json")
        guard let data = try? Data(contentsOf: jsonURL) else {
            throw .transcriptionFailed("whisper.cpp didn't write a transcript.")
        }
        return try WhisperOutputParser.parse(data)
    }

    private func run(
        wav: URL,
        model: URL,
        language: String,
        outputBase: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws(WhisperError) -> ProcessResult {
        let arguments = [
            "--model", model.path(percentEncoded: false),
            "--file", wav.path(percentEncoded: false),
            "--language", language,
            "--threads", String(Self.threadCount),
            "--output-json", "--output-json-full",
            "--output-file", outputBase.path(percentEncoded: false),
            "--print-progress", "--no-prints",
        ]
        // whisper.cpp may re-decode a stretch and report a lower percentage; never move backwards.
        let tracker = MonotonicProgress(report: progress)
        do {
            return try await ProcessRunner.run(whisperCLI, arguments: arguments) { line in
                if let fraction = Self.progress(from: line) { tracker.update(fraction) }
            }
        } catch {
            switch error {
            case .cancelled: throw .cancelled
            case .launchFailed(let reason): throw .transcriptionFailed("whisper.cpp couldn't be started: \(reason)")
            }
        }
    }

    /// Parses `whisper_print_progress_callback: progress =  41%`.
    static func progress(from line: String) -> Double? {
        guard line.contains("progress ="), let equals = line.lastIndex(of: "=") else { return nil }
        let number = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "%", with: "")
        return Double(number).map { min(1, max(0, $0 / 100)) }
    }

    private static var threadCount: Int {
        min(8, max(2, ProcessInfo.processInfo.activeProcessorCount))
    }

    private static func lastMeaningfulLine(of output: String) -> String? {
        output.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last { !$0.isEmpty && !$0.contains("progress =") }
    }
}
