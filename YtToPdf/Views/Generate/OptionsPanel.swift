import SwiftUI

struct OptionsPanel: View {
    @Bindable var model: GenerateViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(title: "Options")
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 28, verticalSpacing: 16) {
                GridRow {
                    rowLabel("Timestamps")
                    Picker("Timestamps", selection: $model.options.timestampMode) {
                        ForEach(TranscriptOptions.TimestampMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                GridRow {
                    rowLabel("Format")
                    Picker("Format", selection: $model.options.timestampStyle) {
                        ForEach(TranscriptOptions.TimestampStyle.allCases) { style in
                            Text(style.label).monospacedDigit().tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .disabled(model.options.timestampMode == .off)
                }

                Divider().gridCellUnsizedAxes(.horizontal)

                GridRow {
                    rowLabel("Language")
                    languageControl
                }
                GridRow {
                    rowLabel("Captions")
                    Toggle("Prefer manual captions", isOn: $model.options.preferManualCaptions)
                }
                if model.willUseWhisper {
                    GridRow {
                        rowLabel("Model")
                        WhisperModelPicker(selection: $model.options.whisperModel, store: model.modelStore)
                    }
                    .transition(.opacity)
                }

                Divider().gridCellUnsizedAxes(.horizontal)

                GridRow(alignment: .top) {
                    rowLabel("Export")
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Include video info header", isOn: $model.options.includeVideoInfo)
                        Toggle("Clickable timestamps in PDF", isOn: $model.options.clickableTimestamps)
                            .disabled(model.options.timestampMode == .off)
                    }
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .surface()
        }
        .animation(.smooth, value: model.willUseWhisper)
    }

    private func rowLabel(_ title: String) -> some View {
        Text(title)
            .foregroundStyle(.secondary)
            .gridColumnAlignment(.trailing)
    }

    @ViewBuilder
    private var languageControl: some View {
        let options = model.languageOptions
        if options.isEmpty {
            Text("Detected automatically from speech")
                .foregroundStyle(.secondary)
        } else {
            Picker("Language", selection: $model.languageCode) {
                ForEach(options) { option in
                    Text("\(option.name) · \(kinds(of: option))")
                        .tag(Optional(option.languageCode))
                }
            }
            .labelsHidden()
            .fixedSize()
        }
    }

    private func kinds(of option: CaptionTrackSelector.LanguageOption) -> String {
        switch (option.hasManual, option.hasAutomatic) {
        case (true, true): "manual & auto"
        case (true, false): "manual"
        default: "auto-generated"
        }
    }
}

struct WhisperModelPicker: View {
    @Binding var selection: WhisperModel
    let store: WhisperModelStore

    var body: some View {
        Picker("Whisper model", selection: $selection) {
            ForEach(WhisperModel.allCases) { model in
                Text(label(for: model)).tag(model)
            }
        }
        .labelsHidden()
        .fixedSize()
    }

    private func label(for model: WhisperModel) -> String {
        let size = ByteCountFormatter.string(fromByteCount: model.approximateBytes, countStyle: .file)
        return store.isInstalled(model) ? "\(model.displayName) · downloaded" : "\(model.displayName) · \(size) download"
    }
}
