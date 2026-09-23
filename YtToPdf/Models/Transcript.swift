import Foundation

/// Where a transcript's text came from.
nonisolated enum TranscriptSource: String, Codable, Sendable, CaseIterable {
    case manualCaptions
    case autoCaptions
    case whisper

    var label: String {
        switch self {
        case .manualCaptions: "Manual captions"
        case .autoCaptions: "Auto-generated captions"
        case .whisper: "Transcribed locally"
        }
    }
}

/// A single word (or the smallest caption fragment available) with its time range in seconds.
nonisolated struct TimedWord: Codable, Sendable, Hashable {
    var text: String
    var start: TimeInterval
    var end: TimeInterval
}

nonisolated struct TranscriptSentence: Codable, Sendable, Hashable {
    var words: [TimedWord]

    var start: TimeInterval { words.first?.start ?? 0 }
    var end: TimeInterval { words.last?.end ?? 0 }
    var text: String { words.map(\.text).joined(separator: " ") }
}

nonisolated struct TranscriptParagraph: Codable, Sendable, Hashable {
    var sentences: [TranscriptSentence]

    var start: TimeInterval { sentences.first?.start ?? 0 }
    var end: TimeInterval { sentences.last?.end ?? 0 }
    var text: String { sentences.map(\.text).joined(separator: " ") }
}

/// A fully parsed transcript, with timing preserved down to word or fragment level.
nonisolated struct Transcript: Codable, Sendable, Hashable {
    var paragraphs: [TranscriptParagraph]
    var languageCode: String
    var source: TranscriptSource

    var words: [TimedWord] {
        paragraphs.flatMap { $0.sentences.flatMap(\.words) }
    }

    var wordCount: Int {
        words.reduce(0) { $0 + $1.text.split(whereSeparator: \.isWhitespace).count }
    }

    var plainText: String {
        paragraphs.map(\.text).joined(separator: "\n\n")
    }
}
