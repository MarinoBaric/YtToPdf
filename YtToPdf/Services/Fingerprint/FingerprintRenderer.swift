import CoreGraphics
import Foundation

/// Draws a Speech Fingerprint into any Core Graphics context: the app's `Canvas`, a bitmap,
/// or a PDF page.
nonisolated enum FingerprintRenderer {
    struct Style {
        var color: CGColor
        /// Opacity at the right-hand end of the gradient; the left end is fully opaque.
        var endOpacity: CGFloat = 0.4
        /// When set, bars in this time range are drawn in full colour and the rest faded:
        /// the running header's "you are here" mode.
        var highlight: ClosedRange<TimeInterval>?
        var fadedOpacity: CGFloat = 0.2
        /// 0...1 entrance animation progress.
        var growth: Double = 1
        /// True for PDF contexts, whose y axis points up; flips the gradient's tilt to match.
        var yAxisPointsUp = false

        init(color: CGColor) {
            self.color = color
        }
    }

    static func draw(_ fingerprint: SpeechFingerprint, in context: CGContext, rect: CGRect, style: Style) {
        let marks = FingerprintGeometry.marks(for: fingerprint, in: rect, growth: style.growth)
        guard !marks.isEmpty else { return }

        context.saveGState()
        defer { context.restoreGState() }

        if let highlight = style.highlight {
            let lit = fingerprint.slices(overlapping: highlight)
            let isLit: (FingerprintGeometry.Mark) -> Bool = { lit?.contains($0.index) == true }
            fill(marks.filter { !isLit($0) }, in: context, color: style.color.copy(alpha: style.fadedOpacity) ?? style.color)
            fill(marks.filter(isLit), in: context, color: style.color)
        } else {
            drawGradient(marks, in: context, rect: rect, style: style, tilt: fingerprint.variation.gradientAngle)
        }
    }

    /// Renders to a bitmap, for previews and tests.
    static func image(_ fingerprint: SpeechFingerprint, size: CGSize, scale: CGFloat = 2, style: Style, background: CGColor? = nil) -> CGImage? {
        let width = Int((size.width * scale).rounded()), height = Int((size.height * scale).rounded())
        guard width > 0, height > 0,
              let context = CGContext(
                  data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }

        context.scaleBy(x: scale, y: scale)
        if let background {
            context.setFillColor(background)
            context.fill(CGRect(origin: .zero, size: size))
        }
        var bitmapStyle = style
        bitmapStyle.yAxisPointsUp = true
        draw(fingerprint, in: context, rect: CGRect(origin: .zero, size: size), style: bitmapStyle)
        return context.makeImage()
    }

    // MARK: - Drawing

    private static func path(for marks: [FingerprintGeometry.Mark]) -> CGPath {
        let path = CGMutablePath()
        for mark in marks {
            if mark.isDot {
                path.addEllipse(in: mark.rect)
            } else {
                let radius = min(mark.rect.width, mark.rect.height) / 2
                path.addRoundedRect(in: mark.rect, cornerWidth: radius, cornerHeight: radius)
            }
        }
        return path
    }

    private static func fill(_ marks: [FingerprintGeometry.Mark], in context: CGContext, color: CGColor) {
        guard !marks.isEmpty else { return }
        context.addPath(path(for: marks))
        context.setFillColor(color)
        context.fillPath()
    }

    /// Fills the marks with the accent colour fading from full to `endOpacity`, left to right,
    /// along the fingerprint's seeded tilt.
    private static func drawGradient(_ marks: [FingerprintGeometry.Mark], in context: CGContext, rect: CGRect, style: Style, tilt: Double) {
        let start = style.color
        let end = style.color.copy(alpha: style.color.alpha * style.endOpacity) ?? style.color
        guard let gradient = CGGradient(colorsSpace: style.color.colorSpace, colors: [start, end] as CFArray, locations: [0, 1]) else {
            fill(marks, in: context, color: style.color)
            return
        }

        let angle = style.yAxisPointsUp ? -tilt : tilt
        let halfWidth = rect.width / 2
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let offset = CGPoint(x: cos(angle) * halfWidth, y: sin(angle) * halfWidth)

        context.addPath(path(for: marks))
        context.clip()
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: center.x - offset.x, y: center.y - offset.y),
            end: CGPoint(x: center.x + offset.x, y: center.y + offset.y),
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )
    }
}
