import Foundation
import UniformTypeIdentifiers

/// The formats a transcript can be exported to.
nonisolated enum ExportFormat: String, CaseIterable, Identifiable, Sendable {
    case pdf
    case plainText
    case markdown
    case subtitles

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pdf: "PDF"
        case .plainText: "Plain Text"
        case .markdown: "Markdown"
        case .subtitles: "Subtitles (SRT)"
        }
    }

    var symbolName: String {
        switch self {
        case .pdf: "doc.richtext"
        case .plainText: "doc.plaintext"
        case .markdown: "text.document"
        case .subtitles: "captions.bubble"
        }
    }

    var contentType: UTType {
        switch self {
        case .pdf: .pdf
        case .plainText: .plainText
        case .markdown: UTType(filenameExtension: "md", conformingTo: .plainText) ?? .plainText
        case .subtitles: UTType(filenameExtension: "srt", conformingTo: .plainText) ?? .plainText
        }
    }

    /// Renders a text format. PDF goes through `PDFExporter` and its preview instead.
    func text(for transcript: Transcript, metadata: VideoMetadata, options: TranscriptOptions) -> String? {
        switch self {
        case .pdf: nil
        case .plainText: PlainTextRenderer.render(transcript, metadata: metadata, options: options)
        case .markdown: MarkdownRenderer.render(transcript, metadata: metadata, options: options)
        case .subtitles: SRTRenderer.render(transcript)
        }
    }
}
