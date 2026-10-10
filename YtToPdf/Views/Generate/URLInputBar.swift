import SwiftUI

/// The large link field with paste and generate controls.
struct URLInputBar: View {
    @Bindable var model: GenerateViewModel
    let clipboardHasLink: Bool

    @FocusState private var isFocused: Bool

    private var generateTitle: String {
        model.transcript == nil ? "Generate" : "Regenerate"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 12) {
                    field
                    Button(action: model.generate) {
                        Label(generateTitle, systemImage: "sparkles")
                            .padding(.horizontal, 6)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.extraLarge)
                    .disabled(!model.canGenerate)
                    .keyboardShortcut(.return, modifiers: .command)
                }
            }
            hint
        }
        .onAppear { isFocused = model.urlText.isEmpty }
    }

    private var field: some View {
        HStack(spacing: 10) {
            Image(systemName: "link")
                .font(.title3)
                .foregroundStyle(.secondary)

            TextField("Paste a YouTube link", text: $model.urlText)
                .textFieldStyle(.plain)
                .font(.title3)
                .focused($isFocused)
                .onSubmit(model.generate)
                .autocorrectionDisabled()

            if !model.urlText.isEmpty {
                Button("Clear", systemImage: "xmark.circle.fill") { model.urlText = "" }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(.tertiary)
                    .transition(.opacity.combined(with: .scale))
            }

            PasteButton(payloadType: String.self) { strings in
                model.paste(strings)
            }
            .labelStyle(.iconOnly)
            .buttonBorderShape(.capsule)
            .help("Paste link from clipboard")
        }
        .padding(.leading, 18)
        .padding(.trailing, 8)
        .frame(height: 52)
        .glassEffect(.regular.interactive(), in: .capsule)
        .animation(.smooth(duration: 0.2), value: model.urlText.isEmpty)
    }

    @ViewBuilder
    private var hint: some View {
        if model.showsInvalidLinkHint {
            Label("That doesn't look like a YouTube video link.", systemImage: "exclamationmark.circle")
                .font(.callout)
                .foregroundStyle(.orange)
                .padding(.leading, 18)
                .transition(.opacity)
        } else if model.urlText.isEmpty, clipboardHasLink {
            HStack(spacing: 8) {
                Image(systemName: "doc.on.clipboard")
                Text("There's a link on your clipboard.")
                PasteButton(payloadType: String.self) { strings in
                    model.paste(strings)
                }
                .controlSize(.small)
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.leading, 18)
            .transition(.opacity)
        }
    }
}
