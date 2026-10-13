import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                GeneralSettingsView()
            }
            Tab("PDF", systemImage: "doc.richtext") {
                PDFSettingsView()
            }
            Tab("Transcription", systemImage: "waveform") {
                TranscriptionSettingsView()
            }
        }
        .frame(width: 560)
        .scenePadding()
    }
}

/// Defaults for new transcripts. The options panel changes them per transcript.
struct GeneralSettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                Picker("Timestamps", selection: $settings.defaultOptions.timestampMode) {
                    ForEach(TranscriptOptions.TimestampMode.allCases) { Text($0.label).tag($0) }
                }
                Picker("Format", selection: $settings.defaultOptions.timestampStyle) {
                    ForEach(TranscriptOptions.TimestampStyle.allCases) { Text($0.label).tag($0) }
                }
                .disabled(settings.defaultOptions.timestampMode == .off)
            } header: {
                Text("Timestamps")
            }

            Section("Captions") {
                Toggle("Prefer manual captions", isOn: $settings.defaultOptions.preferManualCaptions)
                Picker("Transcription model", selection: $settings.defaultOptions.whisperModel) {
                    ForEach(WhisperModel.allCases) { Text($0.displayName).tag($0) }
                }
            }

            Section {
                Toggle("Include video info header", isOn: $settings.defaultOptions.includeVideoInfo)
                Toggle("Clickable timestamps in PDF", isOn: $settings.defaultOptions.clickableTimestamps)
            } header: {
                Text("Export")
            } footer: {
                Text("These apply to new transcripts. Change them for a single transcript in its Options panel.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
