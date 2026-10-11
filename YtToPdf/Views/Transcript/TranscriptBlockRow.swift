import SwiftUI

/// One block of transcript text, with its timestamp in a narrow left column.
struct TranscriptBlockRow: View {
    let block: TranscriptBlock
    let options: TranscriptOptions
    let link: YouTubeLink?
    let highlights: [Range<String.Index>]
    /// Which of `highlights` is the current search match, if any.
    let currentHighlight: Int?

    private var showsColumn: Bool { options.timestampMode != .off }

    private var columnWidth: CGFloat {
        options.timestampStyle == .hoursMinutesSeconds ? 68 : 48
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: showsColumn ? 18 : 0) {
            if showsColumn {
                timestamp
                    .frame(width: columnWidth, alignment: .leading)
            }
            Text(highlightedText)
                .font(.system(size: 15))
                .lineSpacing(6)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var timestamp: some View {
        if let time = block.timestamp {
            let label = Text(TimeFormatting.timestamp(time, style: options.timestampStyle, brackets: false))
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(.tint.opacity(0.75))
            if let link {
                Link(destination: link.watchURL(at: time)) { label }
                    .help("Open the video at \(TimeFormatting.timestamp(time, style: options.timestampStyle, brackets: false))")
                    .pointerStyle(.link)
            } else {
                label
            }
        }
    }

    private var highlightedText: AttributedString {
        let text = block.text
        guard !highlights.isEmpty else { return AttributedString(text) }

        var result = AttributedString()
        var cursor = text.startIndex
        for (index, range) in highlights.enumerated() {
            result += AttributedString(String(text[cursor..<range.lowerBound]))
            var match = AttributedString(String(text[range]))
            let isCurrent = index == currentHighlight
            match.backgroundColor = isCurrent ? Color.accentColor.opacity(0.45) : Color.yellow.opacity(0.38)
            if isCurrent { match.font = .system(size: 15, weight: .semibold) }
            result += match
            cursor = range.upperBound
        }
        result += AttributedString(String(text[cursor...]))
        return result
    }
}
