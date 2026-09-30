import Foundation

/// A short excerpt around the first match, for showing why a history entry matched a search.
nonisolated enum SearchSnippet {
    static func make(from text: String, around query: String, radius: Int = 36) -> String? {
        guard let match = TextSearch.ranges(of: query, in: text).first else { return nil }

        let start = text.index(match.lowerBound, offsetBy: -radius, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(match.upperBound, offsetBy: radius, limitedBy: text.endIndex) ?? text.endIndex
        var excerpt = String(text[start..<end])

        // Cut at word boundaries so the excerpt doesn't start or end mid-word.
        if start != text.startIndex, let space = excerpt.firstIndex(of: " "), space < excerpt.index(excerpt.startIndex, offsetBy: radius) {
            excerpt = String(excerpt[excerpt.index(after: space)...])
        }
        if end != text.endIndex, let space = excerpt.lastIndex(of: " ") {
            excerpt = String(excerpt[..<space])
        }

        let collapsed = excerpt.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return (start == text.startIndex ? "" : "…") + collapsed + (end == text.endIndex ? "" : "…")
    }
}
