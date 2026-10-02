import Foundation

/// Renders a transcript as SubRip subtitles, using the word timing kept from the source.
nonisolated enum SRTRenderer {
    struct Cue: Equatable {
        var start: TimeInterval
        var end: TimeInterval
        var text: String
    }

    /// Readable-subtitle limits: two lines of 42 characters, shown for 1–6 seconds.
    static let maxLineLength = 42
    static let maxCueDuration: TimeInterval = 6
    static let minCueDuration: TimeInterval = 1

    static func render(_ transcript: Transcript) -> String {
        cues(for: transcript).enumerated().map { index, cue in
            "\(index + 1)\n\(timestamp(cue.start)) --> \(timestamp(cue.end))\n\(cue.text)\n"
        }.joined(separator: "\n")
    }

    /// One cue per sentence, split where a sentence is too long to read at once.
    static func cues(for transcript: Transcript) -> [Cue] {
        var cues: [Cue] = []
        for sentence in transcript.paragraphs.flatMap(\.sentences) {
            var chunk: [TimedWord] = []
            for word in sentence.words {
                let candidate = (chunk + [word]).map(\.text).joined(separator: " ")
                let tooLong = candidate.count > maxLineLength * 2
                let tooSlow = (chunk.first.map { word.end - $0.start } ?? 0) > maxCueDuration
                if !chunk.isEmpty, tooLong || tooSlow {
                    cues.append(cue(for: chunk))
                    chunk = []
                }
                chunk.append(word)
            }
            if !chunk.isEmpty { cues.append(cue(for: chunk)) }
        }
        return spaced(cues)
    }

    private static func cue(for words: [TimedWord]) -> Cue {
        let start = words.first?.start ?? 0
        let end = max(words.last?.end ?? start, start)
        return Cue(start: start, end: end, text: wrap(words.map(\.text).joined(separator: " ")))
    }

    /// Keeps cues on screen long enough to read without overlapping the next one.
    private static func spaced(_ cues: [Cue]) -> [Cue] {
        var result = cues
        for index in result.indices {
            let nextStart = index + 1 < result.count ? result[index + 1].start : .infinity
            let wanted = max(result[index].end, result[index].start + minCueDuration)
            result[index].end = max(result[index].start + 0.001, min(wanted, nextStart - 0.001))
        }
        return result
    }

    /// Breaks text longer than one line at the space nearest the middle.
    static func wrap(_ text: String) -> String {
        guard text.count > maxLineLength else { return text }
        let middle = text.index(text.startIndex, offsetBy: text.count / 2)
        let spaces = text.indices.filter { text[$0] == " " }
        guard let split = spaces.min(by: { abs(text.distance(from: middle, to: $0)) < abs(text.distance(from: middle, to: $1)) }) else {
            return text
        }
        return text[..<split] + "\n" + text[text.index(after: split)...]
    }

    /// `01:02:03,456`
    static func timestamp(_ seconds: TimeInterval) -> String {
        let milliseconds = max(0, Int((seconds * 1000).rounded()))
        return String(
            format: "%02d:%02d:%02d,%03d",
            milliseconds / 3_600_000, milliseconds / 60_000 % 60, milliseconds / 1000 % 60, milliseconds % 1000
        )
    }
}
