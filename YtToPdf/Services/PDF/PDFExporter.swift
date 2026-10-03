import CoreGraphics
import CoreText
import Foundation

/// Everything the PDF needs. Sendable so the PDF can be rendered off the main actor.
nonisolated struct PDFExportInput: Sendable {
    var metadata: VideoMetadata
    var transcript: Transcript
    var options: TranscriptOptions
    var theme = PDFTheme()
    /// The user's logo from Settings, or `nil` for YtToPdf's own mark.
    var logo: CGImage?
    var generatedAt = Date.now
}

nonisolated enum PDFExportError: Error, Equatable, Sendable {
    case couldNotCreateDocument
}

extension PDFExportError: LocalizedError {
    var errorDescription: String? { "The PDF couldn't be created." }
}

/// Renders a transcript as a paginated, editorial A4 PDF with embedded Inter.
nonisolated enum PDFExporter {
    @concurrent
    static func makePDF(_ input: PDFExportInput) async throws(PDFExportError) -> Data {
        try render(input)
    }

    static func render(_ input: PDFExportInput) throws(PDFExportError) -> Data {
        let theme = input.theme
        let canvas = PDFCanvas(size: theme.pageSize)
        let fingerprint = SpeechFingerprint(transcript: input.transcript, duration: input.metadata.duration, videoID: input.metadata.id)
        let hero = input.options.includeVideoInfo ? PDFHeroRenderer(input: input, fingerprint: fingerprint) : nil

        let blocks = TranscriptLayout.blocks(for: input.transcript, mode: input.options.timestampMode)
        let layout = PDFBodyLayout(
            blocks: blocks,
            options: input.options,
            theme: theme,
            firstPageTop: hero?.layout(in: nil, page: canvas) ?? theme.bodyTopWithHeader,
            laterPagesTop: theme.bodyTopWithHeader
        )

        let data = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: theme.pageSize)
        let info: [CFString: Any] = [
            kCGPDFContextTitle: input.metadata.title,
            kCGPDFContextAuthor: input.metadata.channel,
            kCGPDFContextSubject: "Transcript of \(input.metadata.webpageURL.absoluteString)",
            kCGPDFContextCreator: "YtToPdf",
        ]
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, info as CFDictionary)
        else { throw .couldNotCreateDocument }

        let pageCount = layout.pages.count
        for (index, page) in layout.pages.enumerated() {
            context.beginPDFPage(nil)
            if index == 0, let hero {
                hero.layout(in: context, page: canvas)
            } else {
                drawRunningHeader(in: context, canvas: canvas, input: input, fingerprint: fingerprint, pageRange: page.timeRange)
            }
            drawBody(page, in: context, canvas: canvas, input: input)
            drawFooter(in: context, canvas: canvas, input: input, number: index + 1, of: pageCount)
            context.endPDFPage()
        }
        context.closePDF()
        return data as Data
    }

    // MARK: - Page parts

    private static func drawBody(_ page: PDFBodyLayout.Page, in context: CGContext, canvas: PDFCanvas, input: PDFExportInput) {
        for line in page.lines {
            canvas.draw(line.line, in: context, x: line.x, baseline: line.baseline)
        }
        let linksTimestamps = input.options.clickableTimestamps
        let link = YouTubeLink(videoID: input.metadata.id)
        for stamp in page.stamps {
            canvas.draw(stamp.line, in: context, x: stamp.x, baseline: stamp.baseline)
            if linksTimestamps, let link {
                canvas.link(link.watchURL(at: stamp.time), in: context, rect: stamp.linkRect)
            }
        }
    }

    /// Small logo on the left; on the right, the slim fingerprint with this page's stretch lit.
    private static func drawRunningHeader(in context: CGContext, canvas: PDFCanvas, input: PDFExportInput, fingerprint: SpeechFingerprint, pageRange: ClosedRange<TimeInterval>?) {
        let theme = input.theme
        let top = theme.marginTop - 16
        let logoHeight: CGFloat = 14
        PDFLogo.draw(input.logo, in: context, page: canvas, origin: CGPoint(x: theme.marginLeft, y: top), height: logoHeight, maxWidth: 90, theme: theme, showsWordmark: true)

        var style = FingerprintRenderer.Style(color: theme.accent)
        style.yAxisPointsUp = true
        style.highlight = pageRange
        let height = theme.headerFingerprintHeight
        let rect = canvas.rect(
            x: theme.pageSize.width - theme.marginRight - theme.headerFingerprintWidth,
            top: top + (logoHeight - height) / 2,
            width: theme.headerFingerprintWidth,
            height: height
        )
        FingerprintRenderer.draw(fingerprint, in: context, rect: rect, style: style)

        canvas.hairline(in: context, from: theme.marginLeft, to: theme.marginLeft + theme.contentWidth, at: top + logoHeight + 12, color: theme.hairline)
    }

    private static func drawFooter(in context: CGContext, canvas: PDFCanvas, input: PDFExportInput, number: Int, of total: Int) {
        let theme = input.theme
        let ruleY = theme.pageSize.height - theme.marginBottom + 8
        canvas.hairline(in: context, from: theme.marginLeft, to: theme.marginLeft + theme.contentWidth, at: ruleY, color: theme.hairline)

        let baseline = ruleY + 15
        let pageLabel = theme.line("Page \(number) of \(total)", .regular, size: 7.5, color: theme.muted, tabular: true)
        let pageX = theme.marginLeft + theme.contentWidth - pageLabel.typographicWidth
        canvas.draw(pageLabel, in: context, x: pageX, baseline: baseline)

        let title = theme.line(input.metadata.title, .regular, size: 7.5, color: theme.muted)
        let titleWidth = min(theme.contentWidth * 0.66, pageX - theme.marginLeft - 24)
        canvas.draw(PDFHeroRenderer.truncated(title, width: titleWidth, theme: theme), in: context, x: theme.marginLeft, baseline: baseline)
    }
}
