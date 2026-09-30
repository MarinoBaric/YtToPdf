import Foundation

/// A run of text that shares one timestamp, the unit every view and export lays out.
nonisolated struct TranscriptBlock: Sendable, Hashable, Identifiable {
    var id: Int
    var paragraphIndex: Int
    /// `false` when a timestamp interval split this block off the paragraph before it.
    var startsParagraph: Bool
    /// The time shown beside the block, or `nil` when it carries none.
    var timestamp: TimeInterval?
    var sentences: [TranscriptSentence]

    var start: TimeInterval { sentences.first?.start ?? 0 }
    var end: TimeInterval { sentences.last?.end ?? 0 }
    var text: String { sentences.map(\.text).joined(separator: " ") }
}

/// Decides where timestamps go, so the preview, copy, exports and PDF all agree.
nonisolated enum TranscriptLayout {
    /// - `off`: one block per paragraph, no timestamps.
    /// - `perParagraph`: one block per paragraph, stamped with its start.
    /// - every N seconds: a paragraph is split at the first sentence that starts in each new
    ///   N-second window, and that block is stamped with the sentence's actual start time.
    static func blocks(for transcript: Transcript, mode: TranscriptOptions.TimestampMode) -> [TranscriptBlock] {
        var blocks: [TranscriptBlock] = []
        var lastWindow = -1

        for (paragraphIndex, paragraph) in transcript.paragraphs.enumerated() {
            guard let interval = mode.interval else {
                blocks.append(TranscriptBlock(
                    id: blocks.count,
                    paragraphIndex: paragraphIndex,
                    startsParagraph: true,
                    timestamp: mode == .perParagraph ? paragraph.start : nil,
                    sentences: paragraph.sentences
                ))
                continue
            }

            var current: TranscriptBlock?
            for sentence in paragraph.sentences {
                let window = Int(sentence.start / interval)
                if window > lastWindow || current == nil {
                    if let finished = current { blocks.append(finished) }
                    let stamped = window > lastWindow
                    lastWindow = max(lastWindow, window)
                    current = TranscriptBlock(
                        id: blocks.count,
                        paragraphIndex: paragraphIndex,
                        startsParagraph: current == nil,
                        timestamp: stamped ? sentence.start : nil,
                        sentences: [sentence]
                    )
                } else {
                    current?.sentences.append(sentence)
                }
            }
            if let finished = current { blocks.append(finished) }
        }
        return blocks
    }
}
