import SwiftUI

/// "Export PDF" as the primary action, with the text formats in its menu.
struct ExportMenu: View {
    let isExportingPDF: Bool
    let export: (ExportFormat) -> Void

    var body: some View {
        Menu {
            ForEach(ExportFormat.allCases) { format in
                Button(format.title, systemImage: format.symbolName) { export(format) }
            }
        } label: {
            if isExportingPDF {
                ProgressView().controlSize(.small)
            } else {
                Label("Export PDF", systemImage: "doc.richtext")
            }
        } primaryAction: {
            export(.pdf)
        }
        .menuStyle(.button)
        .buttonStyle(.glassProminent)
        .fixedSize()
        .disabled(isExportingPDF)
    }
}
