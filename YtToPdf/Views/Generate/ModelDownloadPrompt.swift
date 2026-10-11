import SwiftUI

/// Offers the one-time Whisper model download when a video has no captions.
struct ModelDownloadPrompt: View {
    let suggested: WhisperModel
    let download: (WhisperModel) -> Void
    let dismiss: () -> Void

    @State private var choice: WhisperModel

    init(suggested: WhisperModel, download: @escaping (WhisperModel) -> Void, dismiss: @escaping () -> Void) {
        self.suggested = suggested
        self.download = download
        self.dismiss = dismiss
        _choice = State(initialValue: suggested)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: "waveform.badge.mic")
                .font(.title)
                .foregroundStyle(.tint)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 10) {
                Text("Transcribe on your Mac")
                    .font(.headline)
                Text("This video has no captions, so YtToPdf will transcribe the audio locally with Whisper. Nothing is uploaded. The speech model is a one-time download.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Picker("Model", selection: $choice) {
                    ForEach(WhisperModel.allCases) { model in
                        Text(model.displayName).tag(model)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .padding(.top, 4)

                Text("\(choice.summary) \(ByteCountFormatter.string(fromByteCount: choice.approximateBytes, countStyle: .file)).")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)

                GlassEffectContainer(spacing: 10) {
                    HStack(spacing: 10) {
                        Button("Download & Transcribe", systemImage: "arrow.down.circle") { download(choice) }
                            .buttonStyle(.glassProminent)
                        Button("Not Now", action: dismiss)
                            .buttonStyle(.glass)
                    }
                }
                .padding(.top, 6)
            }
            Spacer(minLength: 0)
        }
        .surface()
        .animation(.smooth, value: choice)
    }
}
