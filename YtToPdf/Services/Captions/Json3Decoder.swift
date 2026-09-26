import Foundation

/// One caption event from a json3 file: a line of text shown from `start` to `end`.
nonisolated struct CaptionCue: Sendable, Equatable {
    struct Fragment: Sendable, Equatable {
        var text: String
        /// Seconds after the cue's start. Only auto captions time individual fragments.
        var offset: TimeInterval?
    }

    var start: TimeInterval
    var end: TimeInterval
    var fragments: [Fragment]
}

nonisolated enum CaptionParserError: Error, Equatable, Sendable {
    case malformed
    case empty
}

extension CaptionParserError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .malformed: "The captions file couldn't be read."
        case .empty: "The captions don't contain any spoken text."
        }
    }
}

/// Reads YouTube's json3 caption format.
nonisolated enum Json3Decoder {
    static func decode(_ data: Data) throws(CaptionParserError) -> [CaptionCue] {
        let file: RawFile
        do {
            file = try JSONDecoder().decode(RawFile.self, from: data)
        } catch {
            throw .malformed
        }

        return (file.events ?? [])
            .compactMap(cue(from:))
            .sorted { $0.start < $1.start }
    }

    private static func cue(from event: RawEvent) -> CaptionCue? {
        guard let segments = event.segs, let startMs = event.tStartMs else { return nil }
        let fragments = segments.compactMap { segment -> CaptionCue.Fragment? in
            guard let text = segment.utf8, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return CaptionCue.Fragment(text: text, offset: segment.tOffsetMs.map { $0 / 1000 })
        }
        guard !fragments.isEmpty else { return nil }

        let start = startMs / 1000
        return CaptionCue(start: start, end: start + (event.dDurationMs ?? 0) / 1000, fragments: fragments)
    }
}

nonisolated private struct RawFile: Decodable {
    var events: [RawEvent]?
}

nonisolated private struct RawEvent: Decodable {
    var tStartMs: Double?
    var dDurationMs: Double?
    var segs: [RawSegment]?
}

nonisolated private struct RawSegment: Decodable {
    var utf8: String?
    var tOffsetMs: Double?
}
