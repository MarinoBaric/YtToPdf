import AppKit
import SwiftUI

/// Gatekeeps the main window behind the tool check.
struct RootView: View {
    @State private var toolCheck = ToolCheckModel()

    var body: some View {
        Group {
            switch toolCheck.state {
            case .checking:
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .missing(let inventory):
                ToolSetupView(inventory: inventory) {
                    await toolCheck.refresh()
                }
                .transition(.opacity)
            case .ready(let inventory):
                MainSplitView(inventory: inventory)
                    .environment(\.toolInventory, inventory)
                    .transition(.opacity)
            }
        }
        .animation(.smooth, value: toolCheck.state)
        .task { await toolCheck.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await toolCheck.refresh() }
        }
    }
}

extension EnvironmentValues {
    @Entry var toolInventory: ToolInventory = .empty
}
