import Foundation

/// Reads whisper-cli's `--output-json-full` file into timed words, one array per segment.
nonisolated enum WhisperOutputParser {
    struct Output: Sendable, Equatable {
        var detectedLanguage: String?
        var segments: [[SpokenWord]]
    }

    static func parse(_ data: Data) throws(WhisperError) -> Output {
        // whisper.cpp can split a multi-byte character across tokens; repair rather than fail.
        let repaired = Data(String(decoding: data, as: UTF8.self).utf8)
        let file: RawFile
        do {
            file = try JSONDecoder().decode(RawFile.self, from: repaired)
        } catch {
            throw .transcriptionFailed("whisper.cpp's output couldn't be read.")
        }
        let segments = (file.transcription ?? []).map(words(in:)).filter { !$0.isEmpty }
        return Output(detectedLanguage: file.result?.language, segments: segments)
    }

    /// Takes word text from the segment (always well formed) and timing from its tokens. If the
    /// two disagree on word count, spreads the segment's time across its words instead.
    private static func words(in segment: RawSegment) -> [SpokenWord] {
        let cleaned = CaptionTextCleaner.clean(segment.text ?? "")
        let texts = cleaned.text.split(separator: " ").map(String.init)
        guard !texts.isEmpty, let offsets = segment.offsets else { return [] }

        let timed = tokenWords(segment.tokens ?? [])
        if timed.count == texts.count {
            return zip(texts, timed).enumerated().map { index, pair in
                SpokenWord(text: pair.0, start: pair.1.start, end: pair.1.end, startsTurn: index == 0 && cleaned.startsTurn)
            }
        }
        return spread(texts, from: offsets.from / 1000, to: offsets.to / 1000, startsTurn: cleaned.startsTurn)
    }

    /// Joins sub-word tokens into words: a token starting with a space begins a new word.
    /// Special tokens (`[_BEG_]`, `[_TT_150]`) and bracketed annotations are dropped.
    private static func tokenWords(_ tokens: [RawToken]) -> [(start: TimeInterval, end: TimeInterval)] {
        var words: [(text: String, start: TimeInterval, end: TimeInterval)] = []
        for token in tokens {
            guard let text = token.text, let offsets = token.offsets, !text.hasPrefix("[_") else { continue }
            let start = offsets.from / 1000
            let end = offsets.to / 1000
            if text.hasPrefix(" ") || words.isEmpty {
                words.append((text.trimmingCharacters(in: .whitespaces), start, end))
            } else {
                words[words.count - 1].text += text
                words[words.count - 1].end = end
            }
        }
        return words
            .filter { !CaptionTextCleaner.clean($0.text).text.isEmpty }
            .map { ($0.start, max($0.end, $0.start)) }
    }

    private static func spread(_ texts: [String], from start: TimeInterval, to end: TimeInterval, startsTurn: Bool) -> [SpokenWord] {
        let duration = max(end - start, 0.1 * Double(texts.count))
        let weights = texts.map { Double($0.count + 1) }
        let total = weights.reduce(0, +)
        var cursor = start
        return texts.enumerated().map { index, text in
            let length = duration * weights[index] / total
            defer { cursor += length }
            return SpokenWord(text: text, start: cursor, end: cursor + length, startsTurn: index == 0 && startsTurn)
        }
    }
}

nonisolated private struct RawFile: Decodable {
    var result: RawResult?
    var transcription: [RawSegment]?
}

nonisolated private struct RawResult: Decodable {
    var language: String?
}

nonisolated private struct RawSegment: Decodable {
    var text: String?
    var offsets: RawOffsets?
    var tokens: [RawToken]?
}

nonisolated private struct RawToken: Decodable {
    var text: String?
    var offsets: RawOffsets?
}

nonisolated private struct RawOffsets: Decodable {
    var from: Double
    var to: Double
}
