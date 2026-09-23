import Foundation

/// The whisper.cpp models YtToPdf offers. Checksums are the SHA-1 values published in
/// whisper.cpp's `models/README.md`.
nonisolated enum WhisperModel: String, CaseIterable, Codable, Identifiable, Sendable {
    case base
    case small
    case medium

    static let `default` = WhisperModel.base

    var id: String { rawValue }

    var displayName: String { rawValue.capitalized }

    var fileName: String { "ggml-\(rawValue).bin" }

    var downloadURL: URL {
        URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(fileName)")
            ?? URL(filePath: "/")
    }

    var sha1: String {
        switch self {
        case .base: "465707469ff3a37a2b9b8d8f89f2f99de7299dac"
        case .small: "55356645c2b361a969dfd0ef2c5a50d530afd8d5"
        case .medium: "fd9727b6e1217c2f614f9b698455c4ffd82463b4"
        }
    }

    var approximateBytes: Int64 {
        switch self {
        case .base: 148_000_000
        case .small: 488_000_000
        case .medium: 1_533_000_000
        }
    }

    var summary: String {
        switch self {
        case .base: "Fast, good for clear speech."
        case .small: "Slower, noticeably more accurate."
        case .medium: "Slowest, best for accents and noisy audio."
        }
    }
}
