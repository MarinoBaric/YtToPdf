import Foundation

/// Removes non-speech annotations and detects speaker-change markers in caption text.
nonisolated enum CaptionTextCleaner {
    struct Cleaned: Equatable {
        var text: String
        var startsTurn: Bool
    }

    /// `[Music]`, `[Applause]`, `♪ lyrics ♪`, and short parentheticals such as `(Laughter)` or
    /// `(Audience)`. Longer parentheses are kept because they are usually real speech.
    private static let annotationPatterns = [
        #"\[[^\]]*\]"#,
        #"♪[^♪]*♪"#,
        #"[♪♫]"#,
        #"\((?:\s*[^\s()]+){1,3}\s*\)"#,
    ].compactMap { try? NSRegularExpression(pattern: $0) }

    private static let entities = ["&amp;": "&", "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&lt;": "<", "&gt;": ">", "&nbsp;": " "]

    static func clean(_ raw: String) -> Cleaned {
        var text = raw
        for (entity, replacement) in entities {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }
        text = text.replacingOccurrences(of: "\n", with: " ")

        var startsTurn = false
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        for marker in [">>", "- ", "– ", "— "] where trimmed.hasPrefix(marker) {
            text = String(trimmed.dropFirst(marker.count))
            // A dash before a lowercase word continues an interrupted sentence ("- because…");
            // only a capitalised line after a dash is a new speaker.
            let continues = marker != ">>" && text.first { $0.isLetter }?.isLowercase == true
            startsTurn = !continues
            break
        }
        if text.contains(">>") {
            startsTurn = true
            text = text.replacingOccurrences(of: ">>", with: " ")
        }

        for pattern in annotationPatterns {
            text = pattern.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: " ")
        }

        let collapsed = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return Cleaned(text: collapsed, startsTurn: startsTurn)
    }
}
