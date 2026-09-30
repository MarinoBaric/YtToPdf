import Foundation

/// Case- and accent-insensitive search used to highlight matches in the transcript preview.
nonisolated enum TextSearch {
    static func ranges(of query: String, in text: String) -> [Range<String.Index>] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }

        var ranges: [Range<String.Index>] = []
        var searchStart = text.startIndex
        while searchStart < text.endIndex,
              let found = text.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive], range: searchStart..<text.endIndex) {
            ranges.append(found)
            searchStart = found.upperBound
        }
        return ranges
    }
}
