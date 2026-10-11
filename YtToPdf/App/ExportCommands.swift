import SwiftUI

/// File › Export… for the focused window's transcript.
struct ExportCommands: Commands {
    @FocusedValue(\.generator) private var generator
    let settings: AppSettings

    var body: some Commands {
        CommandGroup(after: .saveItem) {
            Section {
                ForEach(ExportFormat.allCases) { format in
                    Button("Export as \(format.title)…") { generator?.export(format, settings: settings) }
                        .keyboardShortcut(shortcut(for: format))
                        .disabled(generator?.canExport != true)
                }
            }
        }
    }

    private func shortcut(for format: ExportFormat) -> KeyboardShortcut? {
        format == .pdf ? KeyboardShortcut("e", modifiers: .command) : nil
    }
}

extension FocusedValues {
    @Entry var generator: GenerateViewModel?
}
