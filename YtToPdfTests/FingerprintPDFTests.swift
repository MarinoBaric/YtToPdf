import CoreGraphics
import Foundation
import Testing
@testable import YtToPdf

/// Regression: a clipped gradient fade comes out at full strength in PDFs, because PDF shadings
/// can't carry transparency. Rasterise a real PDF and check the fade survives.
@Suite("Speech Fingerprint in PDF")
struct FingerprintPDFTests {
    @Test func fadeSurvivesInPDF() throws {
        let fingerprint = FingerprintTests.sample
        let size = CGSize(width: 480, height: 60)
        let data = NSMutableData()
        var box = CGRect(origin: .zero, size: size)
        let consumer = try #require(CGDataConsumer(data: data as CFMutableData))
        let pdf = try #require(CGContext(consumer: consumer, mediaBox: &box, nil))
        var style = FingerprintRenderer.Style(color: PDFTheme.defaultAccent)
        style.yAxisPointsUp = true
        pdf.beginPDFPage(nil)
        FingerprintRenderer.draw(fingerprint, in: pdf, rect: CGRect(x: 0, y: 5, width: 480, height: 50), style: style)
        pdf.endPDFPage()
        pdf.closePDF()

        let provider = try #require(CGDataProvider(data: data as CFData))
        let document = try #require(CGPDFDocument(provider))
        let page = try #require(document.page(at: 1))
        let width = 480, height = 60
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let bitmap = try #require(CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        bitmap.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        bitmap.fill(CGRect(x: 0, y: 0, width: width, height: height))
        bitmap.drawPDFPage(page)

        let marks = FingerprintGeometry.marks(for: fingerprint, in: CGRect(x: 0, y: 5, width: 480, height: 50))
        /// Red channel at a bar's centre: the accent is mostly blue, so a lighter (faded) bar
        /// on white paper has more red.
        func red(_ mark: Int) -> Int {
            let x = Int(marks[mark].rect.midX), y = 30
            return Int(pixels[(y * width + x) * 4])
        }
        #expect(red(117) > red(2) + 60, "left \(red(2)) vs right \(red(117))")
    }
}
