import CoreGraphics
import CoreText
import Foundation

/// Page geometry, colours and type for the PDF. All sizes are in points (1/72 in).
nonisolated struct PDFTheme: Sendable {
    // MARK: Page

    static let a4 = CGSize(width: 595.28, height: 841.89)
    static let millimetre: CGFloat = 72 / 25.4

    var pageSize = PDFTheme.a4
    var marginLeft: CGFloat = 58
    var marginRight: CGFloat = 58
    var marginTop: CGFloat = 54
    var marginBottom: CGFloat = 58

    var contentWidth: CGFloat { pageSize.width - marginLeft - marginRight }

    /// Where body text starts on pages with the running header.
    var bodyTopWithHeader: CGFloat { marginTop + 34 }
    /// The lowest point body text may reach, above the footer.
    var bodyBottom: CGFloat { pageSize.height - marginBottom - 14 }

    // MARK: Colour

    var accent: CGColor
    var ink = CGColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1)
    var muted = CGColor(srgbRed: 0.43, green: 0.43, blue: 0.45, alpha: 1)
    var faint = CGColor(srgbRed: 0.56, green: 0.56, blue: 0.58, alpha: 1)
    var hairline = CGColor(srgbRed: 0.85, green: 0.85, blue: 0.87, alpha: 1)

    /// The accent toned down for timestamps, so they guide without shouting.
    var mutedAccent: CGColor { accent.copy(alpha: 0.78) ?? accent }

    init(accent: CGColor = PDFTheme.defaultAccent) {
        self.accent = accent
    }

    static let defaultAccent = CGColor(srgbRed: 0.16, green: 0.33, blue: 0.85, alpha: 1)

    // MARK: Body text

    var bodySize: CGFloat = 10.5
    var bodyLineHeight: CGFloat = 16.6
    /// Space before a new paragraph.
    var paragraphSpacing: CGFloat = 10
    /// Space before a block that a timestamp interval split off mid-paragraph.
    var continuationSpacing: CGFloat = 3
    var timestampGutter: CGFloat = 14

    func timestampColumnWidth(for style: TranscriptOptions.TimestampStyle) -> CGFloat {
        style == .hoursMinutesSeconds ? 50 : 34
    }

    // MARK: Fingerprint

    var bandHeight: CGFloat = 18 * PDFTheme.millimetre
    var headerFingerprintHeight: CGFloat = 4 * PDFTheme.millimetre
    var headerFingerprintWidth: CGFloat = 150

    // MARK: Type

    func attributes(_ face: InterFont, size: CGFloat, color: CGColor, tracking: CGFloat = 0, tabular: Bool = false) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): face.font(size: size, tabularNumbers: tabular),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        ]
        if tracking != 0 {
            attributes[NSAttributedString.Key(kCTKernAttributeName as String)] = tracking
        }
        return attributes
    }

    func line(_ text: String, _ face: InterFont, size: CGFloat, color: CGColor, tracking: CGFloat = 0, tabular: Bool = false) -> CTLine {
        let string = NSAttributedString(string: text, attributes: attributes(face, size: size, color: color, tracking: tracking, tabular: tabular))
        return CTLineCreateWithAttributedString(string)
    }
}
