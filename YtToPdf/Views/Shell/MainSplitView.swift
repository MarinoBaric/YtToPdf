import SwiftData
import SwiftUI

struct MainSplitView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.undoManager) private var undoManager
    @State private var selection: PersistentIdentifier?
    @State private var generator: GenerateViewModel

    init(inventory: ToolInventory) {
        _generator = State(initialValue: GenerateViewModel(inventory: inventory))
    }

    var body: some View {
        NavigationSplitView {
            HistorySidebar(selection: $selection, delete: delete)
                .navigationSplitViewColumnWidth(min: 220, ideal: 270, max: 380)
        } detail: {
            GenerateView(model: generator)
        }
        .onAppear {
            if generator.history == nil { generator.history = HistoryStore(context: modelContext) }
            generator.history?.undoManager = undoManager
        }
        // Picking an entry reopens it; finishing or reopening a transcript selects its entry.
        .onChange(of: selection) { _, id in
            guard let id, id != generator.currentRecordID, let record = generator.history?.record(for: id) else { return }
            generator.open(record)
        }
        .onChange(of: generator.currentRecordID) { _, id in
            if selection != id { selection = id }
        }
    }

    private func delete(_ record: TranscriptRecord) {
        if selection == record.persistentModelID { selection = nil }
        generator.recordWillBeDeleted(record)
        // Read the window's undo manager now; it can still be nil when the view first appears.
        generator.history?.undoManager = undoManager
        generator.history?.delete(record)
    }
}
