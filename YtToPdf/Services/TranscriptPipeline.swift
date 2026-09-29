import Foundation

/// Produces a transcript for a video: captions when YouTube has them, local Whisper otherwise.
nonisolated struct TranscriptPipeline: Sendable {
    enum Step: Int, CaseIterable, Comparable, Sendable {
        case fetchingInfo
        case downloadingCaptions
        case downloadingAudio
        case transcribing
        case formatting

        static func < (lhs: Step, rhs: Step) -> Bool { lhs.rawValue < rhs.rawValue }

        var title: String {
            switch self {
            case .fetchingInfo: "Fetching info"
            case .downloadingCaptions: "Downloading captions"
            case .downloadingAudio: "Downloading audio"
            case .transcribing: "Transcribing"
            case .formatting: "Formatting"
            }
        }
    }

    struct Progress: Sendable, Equatable {
        var step: Step
        /// 0...1 when the step can measure itself, `nil` when it can't.
        var fraction: Double?
    }

    struct Request: Sendable {
        var metadata: VideoMetadata
        /// Caption language to use, or `nil` for the video's default.
        var languageCode: String?
        var preferManualCaptions = true
        var whisperModel = WhisperModel.default
    }

    let youTube: YouTubeService
    let converter: AudioConverter
    let whisper: WhisperService
    let models: WhisperModelStore
    var assembler = TranscriptAssembler()

    init(inventory: ToolInventory, models: WhisperModelStore = WhisperModelStore()) throws(PipelineError) {
        do {
            youTube = try YouTubeService(inventory: inventory)
            converter = AudioConverter(ffmpeg: try inventory.url(for: .ffmpeg))
            whisper = WhisperService(whisperCLI: try inventory.url(for: .whisper))
        } catch {
            throw .tools(error)
        }
        self.models = models
    }

    /// `@concurrent` so decoding yt-dlp's large JSON never runs on the caller's (main) actor.
    @concurrent
    func fetchMetadata(for link: YouTubeLink) async throws(PipelineError) -> VideoMetadata {
        do {
            return try await youTube.fetchMetadata(for: link)
        } catch {
            throw .youTube(error)
        }
    }

    /// `@concurrent` so parsing and assembling run off the main actor.
    @concurrent
    func transcribe(
        _ request: Request,
        progress: @escaping @Sendable (Progress) -> Void
    ) async throws(PipelineError) -> Transcript {
        guard let link = YouTubeLink(videoID: request.metadata.id) else { throw .youTube(.invalidURL) }

        return try await TemporaryWorkspace.withDirectory { directory throws(PipelineError) in
            if let transcript = try await captionTranscript(request, link: link, directory: directory, progress: progress) {
                return transcript
            }
            return try await whisperTranscript(request, link: link, directory: directory, progress: progress)
        }
    }

    // MARK: - Captions

    /// Returns `nil` when the video has no usable captions, so the caller falls back to Whisper.
    private func captionTranscript(
        _ request: Request,
        link: YouTubeLink,
        directory: URL,
        progress: @escaping @Sendable (Progress) -> Void
    ) async throws(PipelineError) -> Transcript? {
        let metadata = request.metadata
        guard let language = request.languageCode ?? CaptionTrackSelector.defaultLanguage(for: metadata, preferred: nil),
              let track = CaptionTrackSelector.track(for: metadata, languageCode: language, preferManual: request.preferManualCaptions)
        else { return nil }

        progress(Progress(step: .downloadingCaptions, fraction: nil))
        let data: Data
        do {
            data = try await youTube.downloadCaptions(track, for: link, into: directory)
        } catch .captionsUnavailable {
            return nil
        } catch {
            throw .youTube(error)
        }

        progress(Progress(step: .formatting, fraction: nil))
        do {
            return try CaptionParser.parse(
                json3: data,
                languageCode: track.languageCode,
                source: track.isAutomatic ? .autoCaptions : .manualCaptions,
                assembler: assembler
            )
        } catch .empty {
            return nil
        } catch {
            throw .captions(error)
        }
    }

    // MARK: - Whisper

    private func whisperTranscript(
        _ request: Request,
        link: YouTubeLink,
        directory: URL,
        progress: @escaping @Sendable (Progress) -> Void
    ) async throws(PipelineError) -> Transcript {
        let modelURL: URL
        do {
            modelURL = try models.installedURL(for: request.whisperModel)
        } catch {
            throw .whisper(error)
        }

        progress(Progress(step: .downloadingAudio, fraction: 0))
        let audio: URL
        do {
            audio = try await youTube.downloadAudio(for: link, into: directory) { fraction in
                // Downloading is most of this step; conversion is quick.
                progress(Progress(step: .downloadingAudio, fraction: fraction * 0.9))
            }
        } catch {
            throw .youTube(error)
        }

        let wav = directory.appending(path: "speech.wav")
        do throws(WhisperError) {
            try await converter.convertToWhisperWAV(audio, output: wav, duration: request.metadata.duration) { fraction in
                progress(Progress(step: .downloadingAudio, fraction: 0.9 + fraction * 0.1))
            }
            try? FileManager.default.removeItem(at: audio)

            progress(Progress(step: .transcribing, fraction: 0))
            let output = try await whisper.transcribe(wav, model: modelURL, language: whisperLanguage(for: request)) { fraction in
                progress(Progress(step: .transcribing, fraction: fraction))
            }

            progress(Progress(step: .formatting, fraction: nil))
            let language = output.detectedLanguage ?? request.languageCode ?? request.metadata.languageCode ?? "und"
            let words = CaptionDeduplicator.merge(output.segments)
            let paragraphs = assembler.assemble(words, languageCode: language)
            guard !paragraphs.isEmpty else { throw WhisperError.noSpeechDetected }

            return Transcript(paragraphs: paragraphs, languageCode: language, source: .whisper)
        } catch {
            throw .whisper(error)
        }
    }

    /// The language to tell Whisper: the user's pick, else what YouTube reports, else detect.
    private func whisperLanguage(for request: Request) -> String? {
        request.languageCode ?? request.metadata.languageCode
    }
}
