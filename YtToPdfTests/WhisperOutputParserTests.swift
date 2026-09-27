import Foundation
import Testing
@testable import YtToPdf

@Suite("Whisper output parsing")
struct WhisperOutputParserTests {
    /// Shaped like `whisper-cli --output-json-full`: special tokens, sub-word tokens, an
    /// annotation-only segment, and a segment whose tokens don't line up with its text.
    private static let sample = Data("""
    {
      "systeminfo": "AVX = 0", "model": {"type": "base"},
      "params": {"model": "ggml-base.bin", "language": "auto", "translate": false},
      "result": {"language": "hr"},
      "transcription": [
        {"timestamps": {"from": "00:00:00,000", "to": "00:00:03,000"}, "offsets": {"from": 0, "to": 3000},
         "text": " Dobar dan, kuhamo danas.",
         "tokens": [
           {"text": "[_BEG_]", "offsets": {"from": 0, "to": 0}, "id": 50364, "p": 1},
           {"text": " Do", "offsets": {"from": 100, "to": 300}, "id": 1, "p": 0.9},
           {"text": "bar", "offsets": {"from": 300, "to": 500}, "id": 2, "p": 0.9},
           {"text": " dan", "offsets": {"from": 600, "to": 900}, "id": 3, "p": 0.9},
           {"text": ",", "offsets": {"from": 900, "to": 950}, "id": 4, "p": 0.9},
           {"text": " kuhamo", "offsets": {"from": 1200, "to": 1800}, "id": 5, "p": 0.9},
           {"text": " danas", "offsets": {"from": 1900, "to": 2500}, "id": 6, "p": 0.9},
           {"text": ".", "offsets": {"from": 2500, "to": 2600}, "id": 7, "p": 0.9},
           {"text": "[_TT_150]", "offsets": {"from": 3000, "to": 3000}, "id": 50514, "p": 1}
         ]},
        {"offsets": {"from": 3000, "to": 6000}, "text": " [Music]",
         "tokens": [{"text": " [", "offsets": {"from": 3000, "to": 3100}}, {"text": "Music", "offsets": {"from": 3100, "to": 3500}},
                    {"text": "]", "offsets": {"from": 3500, "to": 3600}}]},
        {"offsets": {"from": 6000, "to": 8000}, "text": " Prvo jaja.",
         "tokens": [{"text": " Prvojaja.", "offsets": {"from": 6000, "to": 8000}}]}
      ]
    }
    """.utf8)

    @Test func joinsSubwordTokensAndKeepsTheirTiming() throws {
        let output = try WhisperOutputParser.parse(Self.sample)
        #expect(output.detectedLanguage == "hr")
        #expect(output.segments.count == 2, "the [Music] segment is dropped")

        let first = try #require(output.segments.first)
        #expect(first.map(\.text) == ["Dobar", "dan,", "kuhamo", "danas."])
        #expect(first[0].start == 0.1)
        #expect(first[0].end == 0.5)
        #expect(first[3].end == 2.6)
    }

    @Test func fallsBackToSpreadingTimeWhenTokensDisagree() throws {
        let output = try WhisperOutputParser.parse(Self.sample)
        let last = try #require(output.segments.last)
        #expect(last.map(\.text) == ["Prvo", "jaja."])
        #expect(last.first?.start == 6.0)
        #expect(abs((last.last?.end ?? 0) - 8.0) < 0.0001)
    }

    @Test func survivesInvalidUTF8() throws {
        var data = Data(#"{"result": {"language": "hr"}, "transcription": [{"offsets": {"from": 0, "to": 1000}, "text": " ka"#.utf8)
        data.append(0xC4) // first byte of "č" with its second byte missing
        data.append(Data(#"o."}]}"#.utf8))
        let output = try WhisperOutputParser.parse(data)
        #expect(output.segments.first?.count == 1)
    }

    @Test func rejectsNonJSON() {
        #expect(throws: WhisperError.self) { try WhisperOutputParser.parse(Data("whisper_init: failed".utf8)) }
    }

    @Test func assembledWhisperOutputIsPunctuatedText() throws {
        let output = try WhisperOutputParser.parse(Self.sample)
        let paragraphs = TranscriptAssembler().assemble(CaptionDeduplicator.merge(output.segments))
        #expect(paragraphs.flatMap(\.sentences).map(\.text) == ["Dobar dan, kuhamo danas.", "Prvo jaja."])
    }

    @Test func repeatedHallucinatedSegmentsAreDropped() {
        let line = ["Hvala", "na", "gledanju."]
        let segments = (0..<3).map { repeat_ in
            line.enumerated().map { index, word in
                SpokenWord(text: word, start: Double(repeat_ * 3 + index), end: Double(repeat_ * 3 + index) + 0.5)
            }
        }
        #expect(CaptionDeduplicator.merge(segments).count == 3)
    }
}
