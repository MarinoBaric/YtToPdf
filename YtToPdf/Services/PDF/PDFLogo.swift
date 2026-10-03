import CoreGraphics
import CoreText
import Foundation

/// Draws the user's logo, or YtToPdf's own mark when none is set.
nonisolated enum PDFLogo {
    /// Draws the logo with its top-left corner at `origin` (top-down page coordinates) and
    /// returns the width used.
    @discardableResult
    static func draw(_ image: CGImage?, in context: CGContext, page: PDFCanvas, origin: CGPoint, height: CGFloat, maxWidth: CGFloat, theme: PDFTheme, showsWordmark: Bool) -> CGFloat {
        if let image {
            let aspect = CGFloat(image.width) / CGFloat(max(image.height, 1))
            var size = CGSize(width: height * aspect, height: height)
            if size.width > maxWidth {
                size = CGSize(width: maxWidth, height: maxWidth / aspect)
            }
            context.interpolationQuality = .high
            context.draw(image, in: page.rect(x: origin.x, top: origin.y, width: size.width, height: size.height))
            return size.width
        }
        return drawDefaultMark(in: context, page: page, origin: origin, height: height, theme: theme, showsWordmark: showsWordmark)
    }

    /// A rounded accent square holding five mirrored bars: the fingerprint in miniature.
    private static func drawDefaultMark(in context: CGContext, page: PDFCanvas, origin: CGPoint, height: CGFloat, theme: PDFTheme, showsWordmark: Bool) -> CGFloat {
        let square = page.rect(x: origin.x, top: origin.y, width: height, height: height)
        context.saveGState()
        context.addPath(CGPath(roundedRect: square, cornerWidth: height * 0.26, cornerHeight: height * 0.26, transform: nil))
        context.setFillColor(theme.accent)
        context.fillPath()

        let bars: [CGFloat] = [0.32, 0.62, 0.9, 0.5, 0.74]
        let inset = height * 0.2
        let pitch = (height - 2 * inset) / CGFloat(bars.count)
        let barWidth = pitch * 0.52
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        for (index, fraction) in bars.enumerated() {
            let barHeight = (height - 2 * inset) * fraction
            let x = square.minX + inset + pitch * (CGFloat(index) + 0.5) - barWidth / 2
            let bar = CGRect(x: x, y: square.midY - barHeight / 2, width: barWidth, height: barHeight)
            context.addPath(CGPath(roundedRect: bar, cornerWidth: barWidth / 2, cornerHeight: barWidth / 2, transform: nil))
        }
        context.fillPath()
        context.restoreGState()

        guard showsWordmark else { return height }
        let wordmark = theme.line("YtToPdf", .semiBold, size: height * 0.5, color: theme.ink, tracking: -0.2)
        let gap = height * 0.32
        let capHeight = CTFontGetCapHeight(InterFont.semiBold.font(size: height * 0.5))
        // Centre the capitals on the mark.
        page.draw(wordmark, in: context, x: origin.x + height + gap, baseline: origin.y + height / 2 + capHeight / 2)
        return height + gap + CTLineGetTypographicBounds(wordmark, nil, nil, nil)
    }
}
