import PDFKit
import SwiftUI
import UniformTypeIdentifiers

/// A rendered PDF waiting to be reviewed and saved.
struct PDFPreview: Identifiable {
    let id = UUID()
    let data: Data
    let suggestedFileName: String
}

/// Shows the PDF before it's saved.
struct PDFPreviewSheet: View {
    let preview: PDFPreview
    let dismiss: () -> Void

    @State private var isSaving = false
    @State private var saveError: String?

    private var pageCount: Int { PDFDocument(data: preview.data)?.pageCount ?? 0 }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            PDFKitView(data: preview.data)
        }
        .frame(minWidth: 640, idealWidth: 760, minHeight: 640, idealHeight: 860)
        .fileExporter(
            isPresented: $isSaving,
            document: ExportFile(data: preview.data, contentType: .pdf),
            contentType: .pdf,
            defaultFilename: preview.suggestedFileName
        ) { result in
            switch result {
            case .success: dismiss()
            case .failure(let error): saveError = error.localizedDescription
            }
        }
        .alert("The PDF couldn't be saved", isPresented: .constant(saveError != nil)) {
            Button("OK") { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(preview.suggestedFileName)
                    .font(.headline)
                    .lineLimit(1)
                Text("\(pageCount) \(pageCount == 1 ? "page" : "pages") · A4")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    Button("Cancel", action: dismiss)
                        .buttonStyle(.glass)
                        .keyboardShortcut(.cancelAction)
                    Button("Save PDF…", systemImage: "square.and.arrow.down") { isSaving = true }
                        .buttonStyle(.glassProminent)
                        .keyboardShortcut("s", modifiers: .command)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}

/// PDFKit's viewer, showing continuous pages on a neutral backdrop.
private struct PDFKitView: NSViewRepresentable {
    let data: Data

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displaysPageBreaks = true
        view.pageShadowsEnabled = true
        view.document = PDFDocument(data: data)
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        if view.document?.dataRepresentation() != data {
            view.document = PDFDocument(data: data)
        }
    }
}

/// Wraps exported bytes (PDF or text) for `fileExporter`.
struct ExportFile: FileDocument {
    static let readableContentTypes: [UTType] = [.pdf, .plainText]

    let data: Data
    let contentType: UTType

    init(data: Data, contentType: UTType) {
        self.data = data
        self.contentType = contentType
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        self.data = data
        contentType = configuration.contentType
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
