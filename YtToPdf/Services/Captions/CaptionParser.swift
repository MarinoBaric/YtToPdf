import Foundation

/// Turns a downloaded json3 caption file into a clean, timed `Transcript`.
nonisolated enum CaptionParser {
    static func parse(
        json3 data: Data,
        languageCode: String,
        source: TranscriptSource,
        assembler: TranscriptAssembler = TranscriptAssembler()
    ) throws(CaptionParserError) -> Transcript {
        let cues = try Json3Decoder.decode(data)
        let isWordTimed = cues.contains { cue in cue.fragments.contains { $0.offset != nil } }

        let cueWords = isWordTimed ? cues.map(wordTimedWords) : lineTimedWords(cues)
        var words = CaptionDeduplicator.merge(cueWords)
        if isWordTimed { estimateWordEnds(&words) }

        let paragraphs = assembler.assemble(words, languageCode: languageCode)
        guard !paragraphs.isEmpty else { throw .empty }
        return Transcript(paragraphs: paragraphs, languageCode: languageCode, source: source)
    }

    // MARK: - Auto captions: one fragment per word

    private static func wordTimedWords(_ cue: CaptionCue) -> [SpokenWord] {
        var words: [SpokenWord] = []
        var pendingTurn = false
        for fragment in cue.fragments {
            let cleaned = CaptionTextCleaner.clean(fragment.text)
            pendingTurn = pendingTurn || cleaned.startsTurn
            let start = cue.start + (fragment.offset ?? 0)
            for token in cleaned.text.split(separator: " ") {
                words.append(SpokenWord(text: String(token), start: start, end: start, startsTurn: pendingTurn))
                pendingTurn = false
            }
        }
        return words
    }

    /// Auto captions only give start times. Estimate each word's length from its letters,
    /// capped by when the next word starts, so pauses stay measurable.
    private static func estimateWordEnds(_ words: inout [SpokenWord]) {
        for index in words.indices {
            let spoken = min(max(0.07 * Double(words[index].text.count) + 0.1, 0.2), 0.7)
            var end = words[index].start + spoken
            if index + 1 < words.endIndex {
                end = min(end, max(words[index].start, words[index + 1].start))
            }
            words[index].end = end
        }
    }

    // MARK: - Manual captions: one timed line per cue

    /// Spreads each line's words across the cue's duration in proportion to their length.
    private static func lineTimedWords(_ cues: [CaptionCue]) -> [[SpokenWord]] {
        cues.enumerated().map { index, cue in
            let cleaned = CaptionTextCleaner.clean(cue.fragments.map(\.text).joined())
            let tokens = cleaned.text.split(separator: " ").map(String.init)
            guard !tokens.isEmpty else { return [] }

            var end = cue.end
            if index + 1 < cues.endIndex, cues[index + 1].start > cue.start {
                end = min(end, cues[index + 1].start)
            }
            let duration = max(end - cue.start, 0.1 * Double(tokens.count))
            let weights = tokens.map { Double($0.count + 1) }
            let total = weights.reduce(0, +)

            var cursor = cue.start
            return tokens.enumerated().map { tokenIndex, token in
                let length = duration * weights[tokenIndex] / total
                defer { cursor += length }
                return SpokenWord(text: token, start: cursor, end: cursor + length, startsTurn: tokenIndex == 0 && cleaned.startsTurn)
            }
        }
    }
}
