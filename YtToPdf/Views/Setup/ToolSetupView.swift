import AppKit
import SwiftUI

/// Shown instead of the main window when a required tool isn't installed.
struct ToolSetupView: View {
    let inventory: ToolInventory
    let recheck: () async -> Void

    @State private var isChecking = false

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                header
                toolList
                commands
                actions
            }
            .frame(maxWidth: 540)
            .padding(.horizontal, 40)
            .padding(.vertical, 56)
            .frame(maxWidth: .infinity)
        }
        .background(.background)
    }

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "shippingbox")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.tint)
                .padding(.bottom, 4)
            Text("One quick setup step")
                .font(.largeTitle.weight(.semibold))
            Text("YtToPdf runs entirely on your Mac using a few free, open-source tools. Install the missing ones with Homebrew, then come back here.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var toolList: some View {
        VStack(spacing: 0) {
            ForEach(ExternalTool.allCases) { tool in
                ToolStatusRow(tool: tool, location: inventory.locations[tool])
                if tool != ExternalTool.allCases.last {
                    Divider().padding(.leading, 52)
                }
            }
        }
        .padding(.vertical, 6)
        .background(.background.secondary, in: .rect(cornerRadius: 16))
    }

    @ViewBuilder
    private var commands: some View {
        VStack(alignment: .leading, spacing: 20) {
            if inventory.homebrewURL == nil {
                CommandBox(
                    title: "1. Install Homebrew",
                    command: ToolInventory.homebrewInstallCommand
                )
            }
            if let installCommand = inventory.installCommand {
                CommandBox(
                    title: inventory.homebrewURL == nil ? "2. Install the tools" : "Run this in Terminal",
                    command: installCommand
                )
            }
        }
    }

    private var actions: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                Button("Open Terminal", systemImage: "terminal", action: openTerminal)
                    .buttonStyle(.glass)
                Button {
                    Task {
                        isChecking = true
                        await recheck()
                        isChecking = false
                    }
                } label: {
                    Label(isChecking ? "Checking…" : "Check Again", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.glassProminent)
                .disabled(isChecking)
            }
            .controlSize(.large)
        }
    }

    private func openTerminal() {
        let terminal = URL(filePath: "/System/Applications/Utilities/Terminal.app")
        NSWorkspace.shared.openApplication(at: terminal, configuration: .init())
    }
}

#Preview {
    ToolSetupView(inventory: .empty) {}
        .frame(width: 760, height: 760)
}
