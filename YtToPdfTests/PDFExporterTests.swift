import AppKit
import CoreGraphics
import Foundation
import PDFKit
import Testing
import UniformTypeIdentifiers
@testable import YtToPdf

@Suite("PDF export")
struct PDFExporterTests {
    // MARK: - Fixture

    /// A deterministic synthetic transcript: ~2,600 words in paragraphs of 40–90 words,
    /// one word every 0.38 s, so it runs about 16 minutes and spans several pages.
    static let transcript: Transcript = {
        let vocabulary = ["the", "workshop", "bench", "timber", "joint", "careful", "measure", "plane", "edge", "grain",
                          "glue", "clamp", "square", "chisel", "sharp", "slowly", "then", "we", "check", "again",
                          "board", "finish", "oil", "light", "corner", "steady", "hand", "notice", "how", "it"]
        var random = SplitMix64(seed: 42)
        var time = 4.0
        var paragraphs: [TranscriptParagraph] = []
        for _ in 0..<40 {
            var sentences: [TranscriptSentence] = []
            let target = Int(random.next(in: 40...90))
            var count = 0
            while count < target {
                let length = Int(random.next(in: 6...16))
                var words: [TimedWord] = []
                for index in 0..<length {
                    var text = vocabulary[Int(random.next() % UInt64(vocabulary.count))]
                    if index == 0 { text = text.prefix(1).uppercased() + text.dropFirst() }
                    if index == length - 1 { text += "." }
                    words.append(TimedWord(text: text, start: time, end: time + 0.3))
                    time += 0.38
                }
                sentences.append(TranscriptSentence(words: words))
                count += length
                time += 0.6
            }
            paragraphs.append(TranscriptParagraph(sentences: sentences))
            time += 2.5
        }
        return Transcript(paragraphs: paragraphs, languageCode: "en", source: .manualCaptions)
    }()

    static let metadata = VideoMetadata(
        id: "abcdefghijk",
        title: "The Patient Workshop: Hand Tools, Timber and Taking Your Time",
        channel: "Sample Workshop",
        duration: (transcript.words.last?.end ?? 0) + 3,
        uploadDate: Date(timeIntervalSince1970: 1_710_504_000),
        thumbnailURL: nil,
        webpageURL: URL(string: "https://www.youtube.com/watch?v=abcdefghijk")!,
        languageCode: "en", manualCaptions: [], automaticCaptions: []
    )

    static func input(_ configure: (inout TranscriptOptions) -> Void = { _ in }) -> PDFExportInput {
        var options = TranscriptOptions()
        configure(&options)
        return PDFExportInput(metadata: metadata, transcript: transcript, options: options, generatedAt: Date(timeIntervalSince1970: 1_791_000_000))
    }

    static func document(_ input: PDFExportInput) throws -> PDFDocument {
        let data = try PDFExporter.render(input)
        return try #require(PDFDocument(data: data))
    }

    // MARK: - Structure

    @Test func isPaginatedA4() throws {
        let document = try Self.document(Self.input())
        #expect(document.pageCount >= 4)
        for index in 0..<document.pageCount {
            let bounds = try #require(document.page(at: index)).bounds(for: .mediaBox)
            #expect(abs(bounds.width - 595.28) < 0.01 && abs(bounds.height - 841.89) < 0.01)
        }
        #expect(document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String == Self.metadata.title)
        #expect(document.documentAttributes?[PDFDocumentAttribute.creatorAttribute] as? String == "YtToPdf")
    }

    @Test func firstPageHasTheHeroAndEveryPageAFooter() throws {
        let document = try Self.document(Self.input())
        let total = document.pageCount
        let first = try #require(document.page(at: 0)?.string)

        #expect(first.contains("TRANSCRIPT"))
        #expect(first.contains("The Patient Workshop"))
        #expect(first.contains("CHANNEL") && first.contains("Sample Workshop"))
        #expect(first.contains(Self.transcript.wordCount.formatted()))
        #expect(first.contains("youtube.com/watch?v=abcdefghijk"))

        for index in 0..<total {
            let text = try #require(document.page(at: index)?.string)
            #expect(text.contains("Page \(index + 1) of \(total)"))
            if index > 0 { #expect(!text.contains("TRANSCRIPT")) }
        }
    }

    @Test func everyWordAppearsInOrder() throws {
        var input = Self.input()
        input.options.timestampMode = .off
        let document = try Self.document(input)
        let pages = (0..<document.pageCount).compactMap { document.page(at: $0)?.string }
        let words = pages.joined(separator: " ").split(whereSeparator: \.isWhitespace).map(String.init)

        // Walk the transcript and find each word in order in the extracted text.
        var cursor = words.startIndex
        var missing = 0
        for word in Self.transcript.words {
            if let found = words[cursor...].firstIndex(of: word.text) {
                cursor = words.index(after: found)
            } else {
                missing += 1
            }
        }
        #expect(missing == 0)
    }

    @Test func withoutVideoInfoEveryPageGetsTheRunningHeader() throws {
        let document = try Self.document(Self.input { $0.includeVideoInfo = false })
        let first = try #require(document.page(at: 0)?.string)
        #expect(!first.contains("TRANSCRIPT"))
        #expect(!first.contains("CHANNEL"))
        #expect(first.contains("YtToPdf"), "the running header's wordmark")
    }

    // MARK: - Fonts

    @Test func embedsInterAndNothingElse() throws {
        let data = try PDFExporter.render(Self.input())
        let provider = try #require(CGDataProvider(data: data as CFData))
        let document = try #require(CGPDFDocument(provider))

        let fonts = FontCollector() // base font name → embedded
        for number in 1...document.numberOfPages {
            guard let page = document.page(at: number)?.dictionary else { continue }
            var resources: CGPDFDictionaryRef?
            var fontDictionary: CGPDFDictionaryRef?
            guard CGPDFDictionaryGetDictionary(page, "Resources", &resources), let resources,
                  CGPDFDictionaryGetDictionary(resources, "Font", &fontDictionary), let fontDictionary
            else { continue }

            CGPDFDictionaryApplyBlock(fontDictionary, { _, object, info in
                var font: CGPDFDictionaryRef?
                guard CGPDFObjectGetValue(object, .dictionary, &font), let font, let info else { return true }
                let collector = Unmanaged<FontCollector>.fromOpaque(info).takeUnretainedValue()
                var name: UnsafePointer<CChar>?
                CGPDFDictionaryGetName(font, "BaseFont", &name)
                collector.fonts[name.map { String(cString: $0) } ?? "?"] = PDFExporterTests.isEmbedded(font)
                return true
            }, Unmanaged.passUnretained(fonts).toOpaque())
        }

        #expect(!fonts.fonts.isEmpty)
        for (name, embedded) in fonts.fonts {
            #expect(name.contains("Inter"), "unexpected font \(name)")
            #expect(embedded, "\(name) is not embedded")
        }
        #expect(fonts.fonts.keys.contains { $0.contains("InterDisplay-Bold") }, "the title face")
    }

    private final class FontCollector {
        var fonts: [String: Bool] = [:]
    }

    /// Simple fonts keep the file in the descriptor; Type 0 fonts in their descendant's.
    static func isEmbedded(_ font: CGPDFDictionaryRef) -> Bool {
        var descriptor: CGPDFDictionaryRef?
        if CGPDFDictionaryGetDictionary(font, "FontDescriptor", &descriptor), let descriptor {
            var stream: CGPDFStreamRef?
            for key in ["FontFile", "FontFile2", "FontFile3"] where CGPDFDictionaryGetStream(descriptor, key, &stream) {
                return true
            }
            return false
        }
        var descendants: CGPDFArrayRef?
        var descendant: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetArray(font, "DescendantFonts", &descendants), let descendants,
              CGPDFArrayGetDictionary(descendants, 0, &descendant), let descendant
        else { return false }
        return isEmbedded(descendant)
    }

    // MARK: - Timestamps and links

    private func timestampLinks(_ document: PDFDocument) -> [URL] {
        (0..<document.pageCount).flatMap { index in
            (document.page(at: index)?.annotations ?? []).compactMap { annotation -> URL? in
                guard let url = annotation.url, url.absoluteString.contains("&t=") else { return nil }
                return url
            }
        }
    }

    @Test func timestampsAreClickableWhenEnabled() throws {
        let input = Self.input { $0.timestampMode = .every30 }
        let document = try Self.document(input)
        let links = timestampLinks(document)
        let stamped = TranscriptLayout.blocks(for: Self.transcript, mode: .every30).compactMap(\.timestamp)

        #expect(links.count == stamped.count)
        #expect(links.first?.absoluteString == "https://www.youtube.com/watch?v=abcdefghijk&t=4s")
        let first = try #require(document.page(at: 0)?.string)
        #expect(first.contains("00:04"), "the column shows the time without brackets")
    }

    @Test func timestampsAreNotLinkedWhenDisabledOrOff() throws {
        #expect(timestampLinks(try Self.document(Self.input { $0.clickableTimestamps = false })).isEmpty)
        #expect(timestampLinks(try Self.document(Self.input { $0.timestampMode = .off })).isEmpty)
    }

    // MARK: - Layout rules

    @Test(arguments: [
        (10, 4, false, 4),   // everything fits
        (1, 5, false, 0),    // a lone line at the bottom: move on
        (4, 5, false, 3),    // would strand one line on the next page: keep two for it
        (2, 3, false, 0),    // can't keep two on both sides: move the whole block
        (3, 9, false, 3),    // ordinary split
        (0, 4, true, 1),     // a page that can't fit anything still makes progress
    ])
    func keepsLinesTogether(_ fits: Int, _ remaining: Int, _ top: Bool, _ expected: Int) {
        #expect(PDFBodyLayout.linesToPlace(fitting: fits, remaining: remaining, isTopOfPage: top) == expected)
    }

    @Test func pagesCoverTheVideoInOrder() {
        let theme = PDFTheme()
        let layout = PDFBodyLayout(
            blocks: TranscriptLayout.blocks(for: Self.transcript, mode: .perParagraph),
            options: TranscriptOptions(), theme: theme,
            firstPageTop: 360, laterPagesTop: theme.bodyTopWithHeader
        )
        let ranges = layout.pages.compactMap(\.timeRange)
        #expect(ranges.count == layout.pages.count)
        #expect(zip(ranges, ranges.dropFirst()).allSatisfy { $0.upperBound <= $1.lowerBound + 0.001 })
        #expect(layout.pages.flatMap(\.lines).allSatisfy { $0.baseline < theme.bodyBottom + 1 })

        // No block leaves a single line alone on either side of a page break.
        for (page, next) in zip(layout.pages, layout.pages.dropFirst()) {
            guard let last = page.lines.last, let first = next.lines.first, last.blockID == first.blockID else { continue }
            #expect(page.lines.filter { $0.blockID == last.blockID }.count >= 2)
            #expect(next.lines.filter { $0.blockID == first.blockID }.count >= 2)
        }
    }

    @Test func veryLongTitlesAreCappedAtFourLines() throws {
        var input = Self.input()
        input.metadata.title = String(repeating: "An extraordinarily long video title that keeps going ", count: 8)
        let document = try Self.document(input)
        // PDFKit doesn't extract the ellipsis glyph, so count what survived instead: four title
        // lines plus the footer hold far fewer than the eight repeats of the full title.
        let first = try #require(document.page(at: 0)?.string)
        #expect(first.components(separatedBy: "keeps going").count - 1 < 8)
    }

    // MARK: - File name

    @MainActor
    @Test(arguments: [
        ("How Joinery Works", "How Joinery Works – Transcript"),
        ("AC/DC: Live? <2024> | \"Best\" *ever*", "AC DC Live 2024 Best ever – Transcript"),
        ("../../etc/passwd", "etc passwd – Transcript"),
        ("   ", "Transcript – Transcript"),
    ])
    func suggestsSafeFileNames(_ title: String, _ expected: String) {
        #expect(GenerateViewModel.fileName(for: title) == expected)
    }

    @MainActor
    @Test func longTitlesAreShortened() {
        #expect(GenerateViewModel.fileName(for: String(repeating: "a", count: 500)).count <= 120 + " – Transcript".count)
    }

    // MARK: - Visual review

    /// Writes the PDF and a PNG per page when `YTTOPDF_RENDER_DIR` is set.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["YTTOPDF_RENDER_DIR"] != nil))
    func writeSampleRenders() throws {
        let directory = URL(filePath: ProcessInfo.processInfo.environment["YTTOPDF_RENDER_DIR"] ?? "/tmp")
        try Self.writeRenders(Self.input { $0.timestampMode = .every30 }, to: directory, name: "synthetic")
        try Self.writeRenders(Self.input { $0.includeVideoInfo = false; $0.timestampStyle = .hoursMinutesSeconds }, to: directory, name: "synthetic-noinfo")
        var longTitle = Self.input()
        longTitle.metadata.title = String(repeating: "An extraordinarily long video title that keeps going ", count: 8)
        try Self.writeRenders(longTitle, to: directory, name: "synthetic-longtitle", pages: 1)
    }

    static func writeRenders(_ input: PDFExportInput, to directory: URL, name: String, pages: Int = 3) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try PDFExporter.render(input)
        try data.write(to: directory.appending(path: "\(name).pdf"))
        let document = try #require(PDFDocument(data: data))
        for index in 0..<min(pages, document.pageCount) {
            let page = try #require(document.page(at: index))
            let image = page.thumbnail(of: CGSize(width: 1190, height: 1684), for: .mediaBox)
            let tiff = try #require(image.tiffRepresentation)
            let png = try #require(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
            try png.write(to: directory.appending(path: "\(name)-page\(index + 1).png"))
        }
    }
}
