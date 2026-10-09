import Foundation
import Observation
import OSLog
import SwiftData

/// Drives the main screen: link → video info → options → transcript.
@Observable
final class GenerateViewModel {
    enum Activity: Equatable {
        case idle
        case fetchingInfo
        case transcribing(TranscriptPipeline.Progress)
        case downloadingModel(WhisperModel, fraction: Double)

        var isBusy: Bool { self != .idle }
    }

    // MARK: Input

    var urlText = "" {
        didSet { if urlText != oldValue { linkChanged() } }
    }
    var options: TranscriptOptions {
        // Remember timestamp and export choices for the transcript that's open.
        didSet { if options != oldValue, let record = currentRecord { history?.updateOptions(options, for: record) } }
    }
    /// Caption language for this video; reset whenever a new video loads.
    var languageCode: String?

    // MARK: State

    private(set) var metadata: VideoMetadata?
    private(set) var thumbnailData: Data?
    private(set) var transcript: Transcript? {
        didSet { if transcript != oldValue { updateFingerprint() } }
    }
    /// The Speech Fingerprint of the current transcript, computed once per transcript.
    private(set) var fingerprint: SpeechFingerprint?
    private(set) var activity = Activity.idle
    private(set) var error: PipelineError?
    /// Set when the video needs Whisper and the chosen model isn't downloaded yet.
    private(set) var missingModel: WhisperModel?
    private(set) var plannedSteps: [TranscriptPipeline.Step] = GenerationPlan.captionSteps
    /// A rendered PDF waiting in the preview sheet.
    var pdfPreview: PDFPreview?
    /// A text export waiting for the save panel.
    var pendingTextExport: TextExport?
    private(set) var isExportingPDF = false
    /// The history entry being shown, if the transcript has been saved or was reopened.
    private(set) var currentRecord: TranscriptRecord?

    var currentRecordID: PersistentIdentifier? { currentRecord?.persistentModelID }

    var link: YouTubeLink? { YouTubeLink(string: urlText) }

    /// True once the user has typed something that can't be a YouTube link.
    var showsInvalidLinkHint: Bool {
        !urlText.trimmingCharacters(in: .whitespaces).isEmpty && link == nil
    }

    var canGenerate: Bool { link != nil && !activity.isBusy }

    var languageOptions: [CaptionTrackSelector.LanguageOption] {
        metadata.map(CaptionTrackSelector.languageOptions(for:)) ?? []
    }

    /// Whether generating will need local transcription with the current choices.
    var willUseWhisper: Bool {
        guard let metadata else { return false }
        return !GenerationPlan.hasCaptionTrack(metadata, languageCode: languageCode, preferManual: options.preferManualCaptions)
    }

    var whisperModelIsInstalled: Bool { modelStore.isInstalled(options.whisperModel) }

    // MARK: Dependencies

    private let pipeline: TranscriptPipeline?
    private let toolsError: PipelineError?
    let modelStore: WhisperModelStore
    /// Set by the window once its model context is available.
    var history: HistoryStore?
    private var metadataTask: Task<VideoMetadata?, Never>?
    private var workTask: Task<Void, Never>?

    init(inventory: ToolInventory, modelStore: WhisperModelStore = WhisperModelStore(), options: TranscriptOptions = DefaultOptions.load()) {
        self.modelStore = modelStore
        self.options = options
        do {
            pipeline = try TranscriptPipeline(inventory: inventory, models: modelStore)
            toolsError = nil
        } catch {
            pipeline = nil
            toolsError = error
        }
    }

    // MARK: - Link and video info

    func paste(_ strings: [String]) {
        guard let text = strings.first(where: { YouTubeLink(string: $0) != nil }) ?? strings.first else { return }
        urlText = text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func linkChanged() {
        error = nil
        guard let link else {
            metadataTask?.cancel()
            return
        }
        guard link.videoID != metadata?.id else { return }

        cancel()
        metadata = nil
        thumbnailData = nil
        transcript = nil
        currentRecord = nil
        missingModel = nil
        languageCode = nil
        metadataTask = Task { [weak self] in
            // Let fast typing settle before asking YouTube.
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return nil }
            return await self?.loadMetadata(for: link)
        }
    }

    /// Fetches info for `link`, reusing a fetch already in flight for the same video.
    private func loadMetadata(for link: YouTubeLink) async -> VideoMetadata? {
        if let metadata, metadata.id == link.videoID { return metadata }
        guard let pipeline else {
            error = toolsError
            return nil
        }

        if activity == .idle { activity = .fetchingInfo }
        defer { if activity == .fetchingInfo { activity = .idle } }

        do {
            let fetched = try await pipeline.fetchMetadata(for: link)
            guard self.link?.videoID == fetched.id else { return nil }
            metadata = fetched
            languageCode = CaptionTrackSelector.defaultLanguage(for: fetched, preferred: nil)
            thumbnailData = await ThumbnailLoader.load(fetched.thumbnailURL)
            return fetched
        } catch {
            if !error.isCancellation, self.link?.videoID == link.videoID { self.error = error }
            return nil
        }
    }

    // MARK: - Generating

    func generate() {
        guard let link else {
            error = .youTube(.invalidURL)
            return
        }
        guard !activity.isBusy || activity == .fetchingInfo else { return }
        error = nil
        missingModel = nil
        workTask = Task { await run(link) }
    }

    func cancel() {
        workTask?.cancel()
        workTask = nil
        metadataTask?.cancel()
        if activity != .idle { activity = .idle }
    }

    func dismissError() { error = nil }

    func dismissModelPrompt() { missingModel = nil }

    /// Starts over with an empty link field.
    func reset() {
        cancel()
        metadata = nil
        thumbnailData = nil
        transcript = nil
        currentRecord = nil
        urlText = ""
        error = nil
        missingModel = nil
        options = DefaultOptions.load()
    }

    // MARK: - Export

    struct TextExport: Identifiable {
        let id = UUID()
        let file: ExportFile
        let fileName: String
    }

    var canExport: Bool { transcript != nil && metadata != nil }

    func export(_ format: ExportFormat, settings: AppSettings) {
        guard let transcript, let metadata else { return }
        guard let text = format.text(for: transcript, metadata: metadata, options: options) else {
            exportPDF(settings: settings)
            return
        }
        pendingTextExport = TextExport(
            file: ExportFile(data: Data(text.utf8), contentType: format.contentType),
            fileName: Self.fileName(for: metadata.title)
        )
    }

    /// Renders the PDF off the main actor, then opens the preview.
    func exportPDF(settings: AppSettings) {
        guard let transcript, let metadata, !isExportingPDF else { return }
        isExportingPDF = true
        let input = PDFExportInput(
            metadata: metadata,
            transcript: transcript,
            options: options,
            theme: PDFTheme(accent: settings.accent(forThumbnail: thumbnailData)),
            logo: settings.logo
        )
        Task {
            defer { isExportingPDF = false }
            do throws(PDFExportError) {
                let data = try await PDFExporter.makePDF(input)
                pdfPreview = PDFPreview(data: data, suggestedFileName: Self.fileName(for: metadata.title))
            } catch {
                self.error = .export(error)
            }
        }
    }

    /// A safe file name from a video title: no path separators, no leading dots, bounded length.
    static func fileName(for title: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:?%*|\"<>").union(.controlCharacters).union(.newlines)
        let cleaned = title.unicodeScalars.map { forbidden.contains($0) ? " " : String($0) }.joined()
        let collapsed = cleaned.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        let name = collapsed.isEmpty ? "Transcript" : String(collapsed.prefix(120))
        return name + " – Transcript"
    }

    // MARK: - History

    /// Shows a saved transcript without touching the network.
    func open(_ record: TranscriptRecord) {
        let restored: Transcript
        do {
            restored = try record.decodedTranscript()
        } catch {
            self.error = .captions(.malformed)
            return
        }
        cancel()
        error = nil
        missingModel = nil
        // Set the video before the link so changing the link doesn't trigger a fetch.
        let saved = record.decodedMetadata()
        metadata = saved
        currentRecord = nil
        thumbnailData = record.thumbnailData
        transcript = restored
        languageCode = record.languageCode
        urlText = saved.webpageURL.absoluteString
        options = record.decodedOptions() ?? DefaultOptions.load()
        currentRecord = record
    }

    /// Forgets the open transcript if its history entry is being deleted.
    func recordWillBeDeleted(_ record: TranscriptRecord) {
        if currentRecord?.persistentModelID == record.persistentModelID { reset() }
    }

    private func updateFingerprint() {
        guard let transcript, let metadata else {
            fingerprint = nil
            return
        }
        fingerprint = SpeechFingerprint(transcript: transcript, duration: metadata.duration, videoID: metadata.id)
    }

    private func saveToHistory(_ transcript: Transcript, metadata: VideoMetadata) {
        guard let history else { return }
        do {
            currentRecord = try history.save(metadata: metadata, transcript: transcript, thumbnail: thumbnailData, options: options)
        } catch {
            // The transcript is still on screen; only the history entry is missing.
            Logger(subsystem: "YtToPdf", category: "History").error("Saving to history failed: \(String(describing: error), privacy: .public)")
            currentRecord = nil
        }
    }

    private func run(_ link: YouTubeLink) async {
        guard let pipeline else {
            error = toolsError
            return
        }
        transcript = nil
        currentRecord = nil
        activity = .transcribing(.init(step: .fetchingInfo, fraction: nil))

        // Use the info fetched while the user was choosing options, or fetch it now.
        var fetched = metadata?.id == link.videoID ? metadata : nil
        if fetched == nil, let pending = metadataTask { fetched = await pending.value }
        if fetched == nil { fetched = await loadMetadata(for: link) }
        guard let metadata = fetched, !Task.isCancelled else {
            activity = .idle
            return
        }

        plannedSteps = GenerationPlan.steps(for: metadata, languageCode: languageCode, preferManual: options.preferManualCaptions)
        let request = TranscriptPipeline.Request(
            metadata: metadata,
            languageCode: languageCode,
            preferManualCaptions: options.preferManualCaptions,
            whisperModel: options.whisperModel
        )

        let (updates, continuation) = AsyncStream.makeStream(of: TranscriptPipeline.Progress.self, bufferingPolicy: .bufferingNewest(32))
        let listener = Task { [weak self] in
            for await progress in updates { self?.apply(progress) }
        }
        defer {
            continuation.finish()
            listener.cancel()
        }

        do {
            let result = try await pipeline.transcribe(request) { continuation.yield($0) }
            guard !Task.isCancelled else { return }
            transcript = result
            saveToHistory(result, metadata: metadata)
        } catch .whisper(.modelMissing(let model)) {
            missingModel = model
        } catch {
            if !error.isCancellation { self.error = error }
        }
        activity = .idle
    }

    private func apply(_ progress: TranscriptPipeline.Progress) {
        guard case .transcribing = activity else { return }
        if !plannedSteps.contains(progress.step) {
            // Captions turned out empty; the pipeline switched to Whisper.
            plannedSteps = GenerationPlan.whisperSteps
        }
        activity = .transcribing(progress)
    }

    // MARK: - Whisper model

    /// Downloads the missing model, then carries on generating.
    func downloadModelAndContinue(_ model: WhisperModel) {
        options.whisperModel = model
        missingModel = nil
        error = nil
        workTask = Task {
            activity = .downloadingModel(model, fraction: 0)
            let (updates, continuation) = AsyncStream.makeStream(of: Double.self, bufferingPolicy: .bufferingNewest(1))
            // Cancelled in the `defer` below, so capturing `self` strongly can't leak.
            let listener = Task {
                for await fraction in updates {
                    guard case .downloadingModel = activity else { continue }
                    activity = .downloadingModel(model, fraction: fraction)
                }
            }
            defer {
                continuation.finish()
                listener.cancel()
            }

            do throws(WhisperError) {
                try await modelStore.download(model) { continuation.yield($0) }
            } catch {
                activity = .idle
                if error != .cancelled {
                    self.error = .whisper(error)
                } else {
                    missingModel = model
                }
                return
            }
            activity = .idle
            generate()
        }
    }
}

/// Which steps a generation will show, decided from the video's captions.
nonisolated enum GenerationPlan {
    static let captionSteps: [TranscriptPipeline.Step] = [.fetchingInfo, .downloadingCaptions, .formatting]
    static let whisperSteps: [TranscriptPipeline.Step] = [.fetchingInfo, .downloadingAudio, .transcribing, .formatting]

    static func hasCaptionTrack(_ metadata: VideoMetadata, languageCode: String?, preferManual: Bool) -> Bool {
        guard let language = languageCode ?? CaptionTrackSelector.defaultLanguage(for: metadata, preferred: nil) else { return false }
        return CaptionTrackSelector.track(for: metadata, languageCode: language, preferManual: preferManual) != nil
    }

    static func steps(for metadata: VideoMetadata, languageCode: String?, preferManual: Bool) -> [TranscriptPipeline.Step] {
        hasCaptionTrack(metadata, languageCode: languageCode, preferManual: preferManual) ? captionSteps : whisperSteps
    }
}
