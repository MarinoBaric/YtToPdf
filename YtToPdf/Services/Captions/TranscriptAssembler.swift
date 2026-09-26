import Foundation

/// Groups a timed word stream into sentences and paragraphs.
///
/// Punctuated sources (manual captions, Whisper) are split on sentence punctuation. Unpunctuated
/// auto captions are split on pauses, then capitalised and given full stops.
nonisolated struct TranscriptAssembler: Sendable {
    struct Configuration: Sendable {
        /// Silence that ends a sentence in unpunctuated text.
        var sentencePause: TimeInterval = 0.45
        /// Silence that ends a paragraph once it has `minParagraphWords`.
        var paragraphPause: TimeInterval = 1.2
        /// Silence that ends a paragraph once it has reached `targetParagraphWords`.
        var softParagraphPause: TimeInterval = 0.35
        var minSentenceWords = 3
        var maxUnpunctuatedSentenceWords = 28
        var minParagraphWords = 30
        var targetParagraphWords = 80
        var maxParagraphWords = 140
        var maxParagraphDuration: TimeInterval = 75
        /// Words a sentence almost never ends on ("the", "and", "let's"). A short pause after one
        /// is a hesitation, not a full stop. Keys are lowercased with punctuation removed.
        var nonTerminalWords: Set<String> = []
    }

    var configuration = Configuration()

    /// - Parameter languageCode: Enables language-specific pause rules; only English has them.
    func assemble(_ words: [SpokenWord], languageCode: String? = nil) -> [TranscriptParagraph] {
        guard !words.isEmpty else { return [] }
        var assembler = self
        if assembler.configuration.nonTerminalWords.isEmpty, let languageCode {
            assembler.configuration.nonTerminalWords = Self.nonTerminalWords(for: languageCode)
        }
        let punctuated = Self.isPunctuated(words)
        let sentences = punctuated ? assembler.splitOnPunctuation(words) : assembler.splitOnPauses(words).map(Self.polish)
        return assembler.groupIntoParagraphs(sentences)
    }

    static func nonTerminalWords(for languageCode: String) -> Set<String> {
        guard CaptionTrack.baseLanguage(of: languageCode) == "en" else { return [] }
        return [
            "the", "a", "an", "and", "or", "but", "because", "if", "when", "whether", "than",
            "of", "to", "for", "with", "from", "by", "into", "onto",
            "my", "your", "our", "their", "its",
            "i", "im", "ive", "ill", "id", "lets", "were", "gonna", "wanna",
        ]
    }

    // MARK: - Sentences

    /// At least one sentence-ending mark per 40 words means the source punctuates.
    static func isPunctuated(_ words: [SpokenWord]) -> Bool {
        let endings = words.count { endsSentence($0.text) }
        return endings > 0 && endings * 40 >= words.count
    }

    private func splitOnPunctuation(_ words: [SpokenWord]) -> [[SpokenWord]] {
        var sentences: [[SpokenWord]] = []
        var current: [SpokenWord] = []
        for (index, word) in words.enumerated() {
            let pause = index > 0 ? word.start - words[index - 1].end : 0
            if !current.isEmpty, word.startsTurn || pause >= configuration.paragraphPause * 2 {
                sentences.append(current)
                current = []
            }
            current.append(word)
            if Self.endsSentence(word.text) {
                sentences.append(current)
                current = []
            }
        }
        if !current.isEmpty { sentences.append(current) }
        return sentences
    }

    private func splitOnPauses(_ words: [SpokenWord]) -> [[SpokenWord]] {
        var sentences: [[SpokenWord]] = []
        var current: [SpokenWord] = []
        for (index, word) in words.enumerated() {
            let pause = index > 0 ? word.start - words[index - 1].end : 0
            let longEnough = current.count >= configuration.minSentenceWords
            let hesitation = current.last.map { configuration.nonTerminalWords.contains($0.comparisonKey) } ?? false
            let breaksHere = word.startsTurn
                || pause >= configuration.paragraphPause * 2
                || (!hesitation && (pause >= configuration.paragraphPause || (longEnough && pause >= configuration.sentencePause)))
            if !current.isEmpty, breaksHere {
                sentences.append(current)
                current = []
            }
            current.append(word)
            if current.count >= configuration.maxUnpunctuatedSentenceWords {
                let (head, tail) = splitAtLongestPause(current)
                sentences.append(head)
                current = tail
            }
        }
        if !current.isEmpty { sentences.append(current) }
        return sentences
    }

    /// Splits an over-long run at its biggest internal pause, keeping both halves readable.
    private func splitAtLongestPause(_ words: [SpokenWord]) -> ([SpokenWord], [SpokenWord]) {
        let lower = min(8, words.count - 1)
        let candidates = lower..<words.count
        let splitIndex = candidates.max { words[$0].start - words[$0 - 1].end < words[$1].start - words[$1 - 1].end } ?? words.count
        return (Array(words[..<splitIndex]), Array(words[splitIndex...]))
    }

    private static let abbreviations: Set<String> = ["mr.", "mrs.", "ms.", "dr.", "st.", "vs.", "e.g.", "i.e.", "prof.", "jr.", "sr."]
    private static let closingMarks = CharacterSet(charactersIn: "\"'”’)]»")

    static func endsSentence(_ text: String) -> Bool {
        let core = text.trimmingCharacters(in: closingMarks.union(.whitespaces))
        guard let last = core.last, ".?!…".contains(last) else { return false }
        if abbreviations.contains(core.lowercased()) { return false }
        // Initials such as "J." in "J. R. R. Tolkien".
        if core.count == 2, core.first?.isUppercase == true, last == "." { return false }
        return true
    }

    /// Capitalises and punctuates an ASR sentence: "so i think" → "So I think."
    private static func polish(_ sentence: [SpokenWord]) -> [SpokenWord] {
        var words = sentence.map { word -> SpokenWord in
            var word = word
            word.text = capitalizedPronoun(word.text)
            return word
        }
        if let first = words.first?.text, let initial = first.first, initial.isLowercase {
            words[0].text = initial.uppercased() + first.dropFirst()
        }
        if let last = words.indices.last, !endsSentence(words[last].text) {
            words[last].text = words[last].text.trimmingCharacters(in: CharacterSet(charactersIn: ",;:")) + "."
        }
        return words
    }

    private static func capitalizedPronoun(_ text: String) -> String {
        let lower = text.lowercased()
        guard lower == "i" || lower.hasPrefix("i'") || lower.hasPrefix("i’") else { return text }
        return "I" + text.dropFirst()
    }

    // MARK: - Paragraphs

    private func groupIntoParagraphs(_ sentences: [[SpokenWord]]) -> [TranscriptParagraph] {
        var paragraphs: [TranscriptParagraph] = []
        var current: [TranscriptSentence] = []
        var currentWords = 0
        var previousEnd: TimeInterval?

        for sentence in sentences {
            guard let first = sentence.first, let last = sentence.last else { continue }
            let pause = previousEnd.map { first.start - $0 } ?? 0
            let paragraphStart = current.first?.start ?? first.start

            let breaks = !current.isEmpty && (
                first.startsTurn
                    || (pause >= configuration.paragraphPause && currentWords >= configuration.minParagraphWords)
                    || (pause >= configuration.softParagraphPause && currentWords >= configuration.targetParagraphWords)
                    || currentWords + sentence.count > configuration.maxParagraphWords
                    || (currentWords >= configuration.minParagraphWords && first.start - paragraphStart > configuration.maxParagraphDuration)
            )
            if breaks {
                paragraphs.append(TranscriptParagraph(sentences: current))
                current = []
                currentWords = 0
            }

            current.append(TranscriptSentence(words: sentence.map { TimedWord(text: $0.text, start: $0.start, end: $0.end) }))
            currentWords += sentence.count
            previousEnd = last.end
        }
        if !current.isEmpty { paragraphs.append(TranscriptParagraph(sentences: current)) }
        return paragraphs
    }
}
