import CoreGraphics
import CoreText
import Foundation

/// The first page's opening: logo, "TRANSCRIPT" label, title, details and the fingerprint band.
nonisolated struct PDFHeroRenderer {
    let input: PDFExportInput
    let fingerprint: SpeechFingerprint
    var theme: PDFTheme { input.theme }

    /// Draws the hero (when `context` is given) and returns where body text should start.
    /// Called once without a context to measure, then again to draw.
    @discardableResult
    func layout(in context: CGContext?, page: PDFCanvas) -> CGFloat {
        let left = theme.marginLeft
        var y = theme.marginTop

        if let context {
            PDFLogo.draw(input.logo, in: context, page: page, origin: CGPoint(x: left, y: y), height: 26, maxWidth: 160, theme: theme, showsWordmark: true)
        }
        y += 26 + 34

        let label = theme.line("TRANSCRIPT", .semiBold, size: 7.5, color: theme.accent, tracking: 2.2)
        if let context { page.draw(label, in: context, x: left, baseline: y + 7) }
        y += 7 + 14

        y = drawTitle(in: context, page: page, top: y)
        y += 18

        y = drawDetails(in: context, page: page, top: y)
        y += 22

        if let context {
            var style = FingerprintRenderer.Style(color: theme.accent)
            style.yAxisPointsUp = true
            FingerprintRenderer.draw(fingerprint, in: context, rect: page.rect(x: left, top: y, width: theme.contentWidth, height: theme.bandHeight), style: style)
            drawTimeLabels(in: context, page: page, baseline: y + theme.bandHeight + 13)
        }
        y += theme.bandHeight + 13 + 20

        if let context { page.hairline(in: context, from: left, to: left + theme.contentWidth, at: y, color: theme.hairline) }
        return y + 26
    }

    // MARK: - Title

    private func drawTitle(in context: CGContext?, page: PDFCanvas, top: CGFloat) -> CGFloat {
        let size: CGFloat = 25, lineHeight: CGFloat = 30
        let attributed = NSAttributedString(string: input.metadata.title, attributes: theme.attributes(.displayBold, size: size, color: theme.ink, tracking: -0.3))
        let lines = Self.wrap(attributed, width: theme.contentWidth * 0.94, maxLines: 4, theme: theme)
        let ascent = CTFontGetAscent(InterFont.displayBold.font(size: size))

        var y = top
        for line in lines {
            if let context { page.draw(line, in: context, x: theme.marginLeft, baseline: y + ascent) }
            y += lineHeight
        }
        return y
    }

    // MARK: - Details grid

    private struct Detail {
        let label: String
        let value: String
        var link: URL?
        var columns = 1
    }

    private var details: [[Detail]] {
        let metadata = input.metadata, transcript = input.transcript
        let date = metadata.uploadDate.map(TimeFormatting.uploadDate) ?? "Unknown"
        let generated = input.generatedAt.formatted(date: .abbreviated, time: .omitted)
        let language = Locale.current.localizedString(forLanguageCode: transcript.languageCode) ?? transcript.languageCode
        return [
            [
                Detail(label: "Channel", value: metadata.channel),
                Detail(label: "Uploaded", value: date),
                Detail(label: "Duration", value: TimeFormatting.duration(metadata.duration)),
                Detail(label: "Words", value: transcript.wordCount.formatted()),
            ],
            [
                Detail(label: "Source", value: transcript.source.shortLabel),
                Detail(label: "Language", value: language),
                Detail(label: "Generated", value: generated),
                Detail(label: "Video", value: "youtu.be/\(metadata.id)", link: metadata.webpageURL),
            ],
        ]
    }

    private func drawDetails(in context: CGContext?, page: PDFCanvas, top: CGFloat) -> CGFloat {
        let columnWidth = theme.contentWidth / 4
        var y = top
        for row in details {
            var column = 0
            for detail in row {
                let x = theme.marginLeft + CGFloat(column) * columnWidth
                let width = columnWidth * CGFloat(detail.columns) - 12
                if let context {
                    let label = theme.line(detail.label.uppercased(), .medium, size: 6.3, color: theme.faint, tracking: 1.2)
                    page.draw(label, in: context, x: x, baseline: y + 6)
                    let color = detail.link == nil ? theme.ink : theme.accent
                    let value = Self.truncated(theme.line(detail.value, .regular, size: 8.8, color: color, tabular: true), width: width, theme: theme)
                    page.draw(value, in: context, x: x, baseline: y + 19)
                    if let link = detail.link {
                        page.link(link, in: context, rect: CGRect(x: x, y: y + 9, width: min(width, value.typographicWidth), height: 13))
                    }
                }
                column += detail.columns
            }
            y += 32
        }
        return y - 8
    }

    private func drawTimeLabels(in context: CGContext, page: PDFCanvas, baseline: CGFloat) {
        let duration = fingerprint.duration
        let labels = [0, duration / 2, duration].map {
            theme.line(TimeFormatting.duration($0), .regular, size: 7, color: theme.faint, tabular: true)
        }
        let left = theme.marginLeft, width = theme.contentWidth
        page.draw(labels[0], in: context, x: left, baseline: baseline)
        page.draw(labels[1], in: context, x: left + width / 2 - labels[1].typographicWidth / 2, baseline: baseline)
        page.draw(labels[2], in: context, x: left + width - labels[2].typographicWidth, baseline: baseline)
    }

    // MARK: - Helpers

    /// Wraps `string` into at most `maxLines` lines, ending the last with an ellipsis if cut.
    static func wrap(_ string: NSAttributedString, width: CGFloat, maxLines: Int, theme: PDFTheme) -> [CTLine] {
        let typesetter = CTTypesetterCreateWithAttributedString(string)
        var lines: [CTLine] = []
        var start = 0
        while start < string.length, lines.count < maxLines {
            let count = max(1, CTTypesetterSuggestLineBreak(typesetter, start, Double(width)))
            let isLast = lines.count == maxLines - 1 && start + count < string.length
            if isLast {
                let rest = string.attributedSubstring(from: NSRange(location: start, length: string.length - start))
                lines.append(truncated(CTLineCreateWithAttributedString(rest), width: width, theme: theme))
            } else {
                lines.append(CTTypesetterCreateLine(typesetter, CFRange(location: start, length: count)))
            }
            start += count
        }
        return lines
    }

    static func truncated(_ line: CTLine, width: CGFloat, theme: PDFTheme) -> CTLine {
        guard line.typographicWidth > width else { return line }
        let runs = CTLineGetGlyphRuns(line) as? [CTRun] ?? []
        let attributes = runs.first.map { CTRunGetAttributes($0) as? [NSAttributedString.Key: Any] ?? [:] } ?? [:]
        let ellipsis = CTLineCreateWithAttributedString(NSAttributedString(string: "…", attributes: attributes))
        return CTLineCreateTruncatedLine(line, Double(width), .end, ellipsis) ?? line
    }
}
