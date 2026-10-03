import CoreGraphics
import CoreText
import Foundation

/// Breaks the transcript into lines and places them on pages.
///
/// Lines are laid out one by one rather than through a single text frame, so the layout knows
/// exactly which page every line, timestamp and second of video lands on. That drives the
/// timestamp column, clickable links, "Page X of Y" and each page's fingerprint highlight.
nonisolated struct PDFBodyLayout {
    struct Line {
        let line: CTLine
        let x: CGFloat
        /// Top-down page coordinate of the baseline.
        let baseline: CGFloat
        let blockID: Int
        /// The stretch of video this line's words cover.
        let timeRange: ClosedRange<TimeInterval>?
    }

    struct Stamp {
        let line: CTLine
        let x: CGFloat
        let baseline: CGFloat
        let time: TimeInterval
        /// Top-down hit area for the link.
        let linkRect: CGRect
    }

    struct Page {
        var lines: [Line] = []
        var stamps: [Stamp] = []

        var timeRange: ClosedRange<TimeInterval>? {
            let ranges = lines.compactMap(\.timeRange)
            guard let low = ranges.map(\.lowerBound).min(), let high = ranges.map(\.upperBound).max() else { return nil }
            return low...high
        }
    }

    let pages: [Page]

    // MARK: - Building

    init(blocks: [TranscriptBlock], options: TranscriptOptions, theme: PDFTheme, firstPageTop: CGFloat, laterPagesTop: CGFloat) {
        let showsColumn = options.timestampMode != .off
        let columnWidth = showsColumn ? theme.timestampColumnWidth(for: options.timestampStyle) + theme.timestampGutter : 0
        let textX = theme.marginLeft + columnWidth
        let textWidth = theme.contentWidth - columnWidth

        let bodyFont = InterFont.regular.font(size: theme.bodySize)
        let ascent = CTFontGetAscent(bodyFont), descent = CTFontGetDescent(bodyFont)
        let baselineOffset = (theme.bodyLineHeight - ascent - descent) / 2 + ascent

        var pages = [Page()]
        var cursor = firstPageTop
        var isTopOfPage = true

        func newPage() {
            pages.append(Page())
            cursor = laterPagesTop
            isTopOfPage = true
        }

        for block in blocks {
            let typeset = Self.typeset(block, width: textWidth, theme: theme)
            guard !typeset.isEmpty else { continue }

            var remaining = typeset[...]
            var isFirstChunk = true
            while !remaining.isEmpty {
                let spacing = isTopOfPage ? 0 : (isFirstChunk ? (block.startsParagraph ? theme.paragraphSpacing : theme.continuationSpacing) : 0)
                let fits = max(0, Int(((theme.bodyBottom - cursor - spacing) / theme.bodyLineHeight).rounded(.down)))
                let take = Self.linesToPlace(fitting: fits, remaining: remaining.count, isTopOfPage: isTopOfPage)
                if take == 0 {
                    newPage()
                    continue
                }

                cursor += spacing
                for (offset, line) in remaining.prefix(take).enumerated() {
                    let baseline = cursor + baselineOffset
                    pages[pages.count - 1].lines.append(Line(line: line.line, x: textX, baseline: baseline, blockID: block.id, timeRange: line.timeRange))
                    if isFirstChunk, offset == 0, showsColumn, let time = block.timestamp {
                        pages[pages.count - 1].stamps.append(Self.stamp(time, baseline: baseline, options: options, theme: theme))
                    }
                    cursor += theme.bodyLineHeight
                }
                remaining = remaining.dropFirst(take)
                isFirstChunk = false
                isTopOfPage = false
                if !remaining.isEmpty { newPage() }
            }
        }
        self.pages = pages
    }

    /// How many of a block's remaining lines to put on this page.
    ///
    /// Keeps at least two lines together on each side of a page break, so no paragraph leaves a
    /// lone line at the bottom of a page or carries a lone line onto the next. Returns 0 to
    /// mean "start a new page first".
    static func linesToPlace(fitting fits: Int, remaining: Int, isTopOfPage: Bool) -> Int {
        if fits >= remaining { return remaining }
        // Nothing fits at all, even on a fresh page: place what we can rather than loop forever.
        if isTopOfPage { return max(1, min(fits, remaining)) }
        if fits < 2 { return 0 }
        if remaining - fits == 1 {
            // Leave two lines for the next page, if that still keeps two here.
            return fits - 1 >= 2 ? fits - 1 : 0
        }
        return fits
    }

    // MARK: - Typesetting

    private struct TypesetLine {
        let line: CTLine
        let timeRange: ClosedRange<TimeInterval>?
    }

    /// Breaks one block into lines of `width`, noting which words (and so which seconds) each holds.
    private static func typeset(_ block: TranscriptBlock, width: CGFloat, theme: PDFTheme) -> [TypesetLine] {
        let words = block.sentences.flatMap(\.words)
        guard !words.isEmpty else { return [] }

        var text = ""
        var wordRanges: [(range: Range<Int>, word: TimedWord)] = []
        for word in words {
            if !text.isEmpty { text += " " }
            let start = text.utf16.count
            text += word.text
            wordRanges.append((start..<text.utf16.count, word))
        }

        let string = NSAttributedString(string: text, attributes: theme.attributes(.regular, size: theme.bodySize, color: theme.ink))
        let typesetter = CTTypesetterCreateWithAttributedString(string)
        let length = string.length

        var lines: [TypesetLine] = []
        var start = 0
        while start < length {
            let count = max(1, CTTypesetterSuggestLineBreak(typesetter, start, Double(width)))
            let line = CTTypesetterCreateLine(typesetter, CFRange(location: start, length: count))
            let span = start..<(start + count)
            let covered = wordRanges.filter { $0.range.overlaps(span) }.map(\.word)
            let timeRange: ClosedRange<TimeInterval>? = if let first = covered.first, let last = covered.last {
                first.start...max(first.start, last.end)
            } else {
                nil
            }
            lines.append(TypesetLine(line: line, timeRange: timeRange))
            start += count
        }
        return lines
    }

    private static func stamp(_ time: TimeInterval, baseline: CGFloat, options: TranscriptOptions, theme: PDFTheme) -> Stamp {
        let size: CGFloat = 8
        let line = theme.line(
            TimeFormatting.timestamp(time, style: options.timestampStyle, brackets: false),
            .medium, size: size, color: theme.mutedAccent, tracking: 0.2, tabular: true
        )
        let width = line.typographicWidth
        let capHeight = CTFontGetCapHeight(InterFont.medium.font(size: size))
        let linkRect = CGRect(x: theme.marginLeft - 3, y: baseline - capHeight - 4, width: width + 6, height: capHeight + 8)
        return Stamp(line: line, x: theme.marginLeft, baseline: baseline, time: time, linkRect: linkRect)
    }
}
