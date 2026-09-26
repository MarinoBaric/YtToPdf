import Foundation

/// Merges caption cues into one word stream, dropping text that a cue repeats from the cues
/// before it.
///
/// Auto-generated captions roll: each cue often re-shows the tail of the previous one, so the
/// same words arrive two or three times with overlapping times.
nonisolated enum CaptionDeduplicator {
    /// Longest repeated run we look for. Rolling captions repeat at most a line or two.
    private static let maxOverlap = 48
    /// A match this long is a repeat even without timing evidence.
    private static let confidentOverlap = 3
    private static let timingTolerance: TimeInterval = 0.05

    static func merge(_ cues: [[SpokenWord]]) -> [SpokenWord] {
        var output: [SpokenWord] = []
        for cue in cues where !cue.isEmpty {
            let repeated = overlap(between: output, and: cue)
            output.append(contentsOf: cue.dropFirst(repeated))
        }
        return output
    }

    /// How many leading words of `incoming` repeat the trailing words of `existing`.
    static func overlap(between existing: [SpokenWord], and incoming: [SpokenWord]) -> Int {
        let limit = min(existing.count, incoming.count, maxOverlap)
        guard limit > 0 else { return 0 }

        for length in stride(from: limit, through: 1, by: -1) {
            let tail = existing.suffix(length)
            let head = incoming.prefix(length)
            guard zip(tail, head).allSatisfy({ $0.comparisonKey == $1.comparisonKey }),
                  let firstRepeat = head.first, let lastExisting = tail.last
            else { continue }

            // Short matches like "that that" are often genuine speech. Only treat them as repeats
            // when the incoming words start before the existing ones have finished.
            let isRedisplay = firstRepeat.start < lastExisting.end - timingTolerance
            if length >= confidentOverlap || isRedisplay {
                return length
            }
        }
        return 0
    }
}
