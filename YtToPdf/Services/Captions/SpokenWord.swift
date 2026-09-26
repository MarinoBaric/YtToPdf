import Foundation

/// A word on its way from a caption or Whisper source into a `Transcript`.
nonisolated struct SpokenWord: Sendable, Equatable {
    var text: String
    var start: TimeInterval
    var end: TimeInterval
    /// Set when the source marks a change of speaker (`>>` or a leading `- `).
    var startsTurn = false

    /// Lowercased with punctuation stripped, for comparing caption fragments.
    var comparisonKey: String {
        String(text.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }
}
