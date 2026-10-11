import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The main screen: link, video, options, progress and transcript in one calm column.
struct GenerateView: View {
    @Bindable var model: GenerateViewModel
    @Environment(AppSettings.self) private var settings
    @State private var clipboard = ClipboardWatcher()

    private var isEmptyState: Bool {
        model.metadata == nil && model.transcript == nil && model.activity == .idle && model.error == nil
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if isEmptyState {
                        HeroHeader()
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    URLInputBar(model: model, clipboardHasLink: clipboard.hasLink)

                    if let error = model.error {
                        ErrorCard(error: error, retry: model.generate, dismiss: model.dismissError)
                            .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    }

                    videoSection

                    activitySection

                    if let transcript = model.transcript, let metadata = model.metadata {
                        TranscriptPreview(
                            transcript: transcript, metadata: metadata, options: model.options,
                            isExportingPDF: model.isExportingPDF, export: { model.export($0, settings: settings) }
                        ) { id in
                            withAnimation(.smooth) { proxy.scrollTo(id, anchor: .center) }
                        }
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .frame(maxWidth: 780, alignment: .leading)
                .padding(.horizontal, 40)
                .padding(.top, isEmptyState ? 72 : 28)
                .padding(.bottom, 48)
                .frame(maxWidth: .infinity)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .animation(.smooth(duration: 0.35), value: model.activity)
        .animation(.smooth(duration: 0.35), value: model.metadata?.id)
        .animation(.smooth(duration: 0.35), value: model.transcript)
        .animation(.smooth(duration: 0.35), value: model.error)
        .animation(.smooth(duration: 0.35), value: model.missingModel)
        .navigationTitle(model.metadata?.title ?? "YtToPdf")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu("Export", systemImage: "square.and.arrow.up") {
                    ForEach(ExportFormat.allCases) { format in
                        Button(format.title, systemImage: format.symbolName) { model.export(format, settings: settings) }
                    }
                }
                .disabled(!model.canExport || model.isExportingPDF)
            }
            ToolbarItem(placement: .primaryAction) {
                Button("New Transcript", systemImage: "square.and.pencil", action: model.reset)
                    .disabled(isEmptyState)
            }
        }
        .sheet(item: $model.pdfPreview) { preview in
            PDFPreviewSheet(preview: preview) { model.pdfPreview = nil }
        }
        .fileExporter(
            isPresented: Binding(get: { model.pendingTextExport != nil }, set: { if !$0 { model.pendingTextExport = nil } }),
            document: model.pendingTextExport?.file,
            contentType: model.pendingTextExport?.file.contentType ?? .plainText,
            defaultFilename: model.pendingTextExport?.fileName
        ) { _ in
            model.pendingTextExport = nil
        }
        .focusedSceneValue(\.generator, model)
        .task { await clipboard.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await clipboard.refresh() }
        }
    }

    @ViewBuilder
    private var videoSection: some View {
        if let metadata = model.metadata {
            VideoCard(metadata: metadata, thumbnail: model.thumbnailData, source: model.transcript?.source, fingerprint: model.fingerprint)
                .transition(.opacity)
            if model.transcript == nil || !model.activity.isBusy {
                OptionsPanel(model: model)
                    .transition(.opacity)
            }
        } else if model.activity == .fetchingInfo {
            VideoCardPlaceholder()
                .transition(.opacity)
        }
    }

    @ViewBuilder
    private var activitySection: some View {
        switch model.activity {
        case .transcribing(let progress):
            ProgressStepsView(steps: model.plannedSteps, progress: progress, cancel: model.cancel)
                .transition(.opacity)
        case .downloadingModel(let whisperModel, let fraction):
            SingleTaskProgressView(title: "Downloading the \(whisperModel.displayName) speech model", fraction: fraction, cancel: model.cancel)
                .transition(.opacity)
        case .idle, .fetchingInfo:
            if let missing = model.missingModel {
                ModelDownloadPrompt(suggested: missing, download: model.downloadModelAndContinue, dismiss: model.dismissModelPrompt)
                    .transition(.opacity)
            }
        }
    }
}

private struct HeroHeader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Any YouTube video,\nbeautifully transcribed.")
                .font(.system(size: 40, weight: .bold))
                .lineSpacing(2)
            Text("Paste a link to get a clean, timestamped transcript and an editorial PDF. Everything runs on your Mac.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 8)
    }
}
