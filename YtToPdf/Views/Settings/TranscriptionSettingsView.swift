import SwiftUI

/// Download, cancel and delete Whisper models.
struct TranscriptionSettingsView: View {
    @Environment(ModelManager.self) private var models
    @State private var modelToDelete: WhisperModel?
    @State private var deleteError: String?

    var body: some View {
        Form {
            Section {
                ForEach(WhisperModel.allCases) { model in
                    ModelRow(model: model, state: models.state(of: model)) { action in
                        switch action {
                        case .download: models.download(model)
                        case .cancel: models.cancelDownload(model)
                        case .delete: modelToDelete = model
                        }
                    }
                }
            } header: {
                Text("Speech models")
            } footer: {
                Text("Used only for videos without captions. Everything runs on your Mac; models are stored in Application Support › YtToPdf › Models.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: models.refresh)
        .confirmationDialog(
            "Delete the \(modelToDelete?.displayName ?? "") model?",
            isPresented: .constant(modelToDelete != nil),
            presenting: modelToDelete
        ) { model in
            Button("Delete", role: .destructive) {
                do {
                    try models.delete(model)
                } catch {
                    deleteError = error.localizedDescription
                }
                modelToDelete = nil
            }
            Button("Cancel", role: .cancel) { modelToDelete = nil }
        } message: { model in
            Text("You can download it again later (\(ByteCountFormatter.string(fromByteCount: model.approximateBytes, countStyle: .file))).")
        }
        .alert("The model couldn't be deleted", isPresented: .constant(deleteError != nil)) {
            Button("OK") { deleteError = nil }
        } message: {
            Text(deleteError ?? "")
        }
    }
}

private struct ModelRow: View {
    enum Action { case download, cancel, delete }

    let model: WhisperModel
    let state: ModelManager.State
    let perform: (Action) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(model.displayName).font(.headline)
                    if model == .default {
                        Text("Default").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if case .downloading(let fraction) = state {
                    ProgressView(value: fraction)
                        .progressViewStyle(.linear)
                        .frame(maxWidth: 260)
                }
            }
            Spacer()
            button
        }
        .padding(.vertical, 4)
        .animation(.smooth, value: state)
    }

    private var size: String {
        ByteCountFormatter.string(fromByteCount: model.approximateBytes, countStyle: .file)
    }

    private var detail: String {
        switch state {
        case .notInstalled: "\(model.summary) \(size)."
        case .downloading(let fraction): "Downloading… \(Int((fraction * 100).rounded()))%"
        case .installed(let bytes): "Downloaded · \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))"
        case .failed(let message): message
        }
    }

    @ViewBuilder
    private var button: some View {
        switch state {
        case .notInstalled, .failed:
            Button("Download", systemImage: "arrow.down.circle") { perform(.download) }
                .buttonStyle(.glass)
        case .downloading:
            Button("Cancel") { perform(.cancel) }
                .buttonStyle(.glass)
        case .installed:
            Button("Delete", systemImage: "trash", role: .destructive) { perform(.delete) }
                .buttonStyle(.glass)
        }
    }
}
