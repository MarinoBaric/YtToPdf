import Foundation

/// Failures on the local transcription path: model management, audio conversion and whisper.cpp.
nonisolated enum WhisperError: Error, Equatable, Sendable {
    case modelMissing(WhisperModel)
    case modelDownloadFailed(String)
    case modelChecksumMismatch
    case audioConversionFailed(String)
    case transcriptionFailed(String)
    case noSpeechDetected
    case cancelled
}

extension WhisperError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .modelMissing(let model): "The \(model.displayName) transcription model isn't downloaded yet."
        case .modelDownloadFailed: "The transcription model couldn't be downloaded."
        case .modelChecksumMismatch: "The downloaded model was damaged."
        case .audioConversionFailed: "The audio couldn't be prepared for transcription."
        case .transcriptionFailed: "Transcription failed."
        case .noSpeechDetected: "No speech was found in this video."
        case .cancelled: "Cancelled."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .modelMissing(let model):
            "This video has no captions, so YtToPdf will transcribe it on your Mac. That needs a one-time download of about \(ByteCountFormatter.string(fromByteCount: model.approximateBytes, countStyle: .file))."
        case .modelDownloadFailed(let detail): detail
        case .modelChecksumMismatch: "Try downloading it again."
        case .audioConversionFailed(let detail), .transcriptionFailed(let detail): detail
        case .noSpeechDetected: "It may be music only. A larger model in Settings can help with quiet or unclear speech."
        case .cancelled: nil
        }
    }
}
