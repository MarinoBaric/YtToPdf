import Foundation

/// A command-line tool YtToPdf runs via `Process`.
nonisolated enum ExternalTool: String, CaseIterable, Identifiable, Sendable {
    case ytDlp
    case ffmpeg
    case whisper

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ytDlp: "yt-dlp"
        case .ffmpeg: "FFmpeg"
        case .whisper: "whisper.cpp"
        }
    }

    /// Executable names to look for, in order of preference.
    var executableNames: [String] {
        switch self {
        case .ytDlp: ["yt-dlp"]
        case .ffmpeg: ["ffmpeg"]
        case .whisper: ["whisper-cli", "whisper-cpp"]
        }
    }

    var brewFormula: String {
        switch self {
        case .ytDlp: "yt-dlp"
        case .ffmpeg: "ffmpeg"
        case .whisper: "whisper-cpp"
        }
    }

    var purpose: String {
        switch self {
        case .ytDlp: "Fetches video info and captions from YouTube."
        case .ffmpeg: "Prepares audio when a video has no captions."
        case .whisper: "Transcribes that audio on your Mac."
        }
    }
}
