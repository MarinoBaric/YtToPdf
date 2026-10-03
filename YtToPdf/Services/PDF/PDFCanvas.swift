import CoreGraphics
import CoreText
import Foundation

/// Lets page drawing think top-down (y grows towards the bottom of the page, like a layout)
/// while drawing into a PDF context, whose y axis points up.
nonisolated struct PDFCanvas {
    let size: CGSize

    func rect(x: CGFloat, top: CGFloat, width: CGFloat, height: CGFloat) -> CGRect {
        CGRect(x: x, y: size.height - top - height, width: width, height: height)
    }

    func draw(_ line: CTLine, in context: CGContext, x: CGFloat, baseline: CGFloat) {
        context.textMatrix = .identity
        context.textPosition = CGPoint(x: x, y: size.height - baseline)
        CTLineDraw(line, context)
    }

    func hairline(in context: CGContext, from x1: CGFloat, to x2: CGFloat, at top: CGFloat, color: CGColor, width: CGFloat = 0.5) {
        context.saveGState()
        context.setStrokeColor(color)
        context.setLineWidth(width)
        context.move(to: CGPoint(x: x1, y: size.height - top))
        context.addLine(to: CGPoint(x: x2, y: size.height - top))
        context.strokePath()
        context.restoreGState()
    }

    /// Makes `rect` (top-down) a link to `url` in the PDF.
    func link(_ url: URL, in context: CGContext, rect: CGRect) {
        context.setURL(url as CFURL, for: self.rect(x: rect.minX, top: rect.minY, width: rect.width, height: rect.height))
    }
}

nonisolated extension CTLine {
    var typographicWidth: CGFloat { CTLineGetTypographicBounds(self, nil, nil, nil) }
}
