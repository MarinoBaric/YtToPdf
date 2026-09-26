import Foundation
import Testing
@testable import YtToPdf

@Suite("Caption cleanup and deduplication")
struct CaptionCleanupTests {
    private func words(_ text: String, from start: TimeInterval, step: TimeInterval = 0.3) -> [SpokenWord] {
        text.split(separator: " ").enumerated().map { index, word in
            let begin = start + Double(index) * step
            return SpokenWord(text: String(word), start: begin, end: begin + step)
        }
    }

    // MARK: - Text cleaner

    @Test(arguments: [
        ("[Music] welcome back", "welcome back", false),
        ("♪ some lyrics here ♪", "", false),
        ("(Laughter)", "", false),
        ("(Audience) Good morning.", "Good morning.", false),
        ("He said (and I quote, loudly and clearly) no.", "He said (and I quote, loudly and clearly) no.", false),
        (">> Are you ready?", "Are you ready?", true),
        ("- Hi there.\\nHow are you?", "Hi there. How are you?", true),
        ("Tom &amp; Jerry&#39;s show", "Tom & Jerry's show", false),
    ])
    func cleansAnnotations(_ raw: String, _ expected: String, _ turn: Bool) {
        let input = raw.replacingOccurrences(of: "\\n", with: "\n")
        #expect(CaptionTextCleaner.clean(input) == .init(text: expected, startsTurn: turn))
    }

    // MARK: - Deduplicator

    @Test func dropsRolledOverText() {
        let first = words("we need to cut the board", from: 0)
        // The next cue re-shows "cut the board" before continuing.
        let second = words("cut the board to length", from: 0.9)
        let merged = CaptionDeduplicator.merge([first, second])
        #expect(merged.map(\.text).joined(separator: " ") == "we need to cut the board to length")
    }

    @Test func dropsIdenticallyTimedRepeatsEvenWhenShort() {
        let first = words("measure twice", from: 0)
        let repeatCue = [SpokenWord(text: "twice", start: 0.3, end: 0.3), SpokenWord(text: "cut", start: 1.0, end: 1.0)]
        let merged = CaptionDeduplicator.merge([first, repeatCue])
        #expect(merged.map(\.text) == ["measure", "twice", "cut"])
    }

    @Test func keepsGenuineRepetitionInSpeech() {
        let first = words("I think that", from: 0)
        let second = words("that is right", from: 1.0)
        let merged = CaptionDeduplicator.merge([first, second])
        #expect(merged.map(\.text).joined(separator: " ") == "I think that that is right")
    }

    @Test func matchingIgnoresCaseAndPunctuation() {
        let first = words("Okay, so here's the plan.", from: 0)
        let second = words("so here's the plan we glue it", from: 0.5)
        let merged = CaptionDeduplicator.merge([first, second])
        #expect(merged.map(\.text).joined(separator: " ") == "Okay, so here's the plan. we glue it")
    }

    // MARK: - Assembler

    @Test func longUnpunctuatedRunsAreSplitAtTheirLongestPause() {
        var stream = words(Array(repeating: "word", count: 20).joined(separator: " "), from: 0, step: 0.2)
        stream += words(Array(repeating: "more", count: 20).joined(separator: " "), from: 4.3, step: 0.2)
        let sentences = TranscriptAssembler().assemble(stream).flatMap(\.sentences)

        #expect(sentences.count >= 2)
        #expect(sentences.allSatisfy { $0.words.count <= 28 })
        #expect(sentences.first?.words.count == 20)
    }

    @Test func paragraphsBreakOnLongPausesOnceTheyHaveSubstance() throws {
        let first = words(Array(repeating: "Alpha.", count: 35).joined(separator: " "), from: 0)
        let second = words(Array(repeating: "Beta.", count: 10).joined(separator: " "), from: 20)
        let paragraphs = TranscriptAssembler().assemble(first + second)
        try #require(paragraphs.count == 2)
        #expect(paragraphs[1].start == 20)
    }

    @Test func englishPausesAfterFunctionWordsAreHesitations() {
        // "first let's … talk" has a pause after "let's"; "sanding … then" has one after a noun.
        let stream = words("now we can sand the board first let's", from: 0)
            + words("talk about grits and sanding", from: 3.0)
            + words("then we finish", from: 5.0)
        let english = TranscriptAssembler().assemble(stream, languageCode: "en-US").flatMap(\.sentences).map(\.text)
        #expect(english == ["Now we can sand the board first let's talk about grits and sanding.", "Then we finish."])

        // Without the English word list the pause after "let's" still ends the sentence.
        let other = TranscriptAssembler().assemble(stream, languageCode: "hr").flatMap(\.sentences)
        #expect(other.count == 3)
    }

    @Test(arguments: [("Hello.", true), ("Dr.", false), ("J.", false), ("right?\"", true), ("wait…", true), ("so,", false)])
    func detectsSentenceEndings(_ text: String, _ ends: Bool) {
        #expect(TranscriptAssembler.endsSentence(text) == ends)
    }
}
