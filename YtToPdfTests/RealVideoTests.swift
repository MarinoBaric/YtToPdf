import CoreGraphics
import Foundation
import PDFKit
import Synchronization
import Testing
@testable import YtToPdf

/// End-to-end checks against live YouTube videos. Off by default because they need the network
/// and yt-dlp. Run with:
///
///     TEST_RUNNER_YTTOPDF_NETWORK_TESTS=1 xcodebuild test -scheme YtToPdf -only-testing:YtToPdfTests/RealVideoTests
@Suite(
    "Real videos",
    .enabled(if: ProcessInfo.processInfo.environment["YTTOPDF_NETWORK_TESTS"] == "1"),
    .serialized
)
struct RealVideoTests {
    /// A TED talk with human-made captions.
    static let manualCaptionsVideo = "https://www.youtube.com/watch?v=iG9CE55wbtY"
    /// A short woodworking tip with only YouTube's speech recognition.
    static let autoCaptionsVideo = "https://youtu.be/KiE4Pk_gu50"
    /// A Croatian cooking video with no captions of any kind (YouTube has no Croatian ASR).
    static let noCaptionsVideo = "https://www.youtube.com/watch?v=XficW4OcFM0"
    /// Workshop footage over music: no captions and almost no speech.
    static let musicOnlyVideo = "https://www.youtube.com/watch?v=_K6W1MGyhkY"

    private func service() throws -> YouTubeService {
        try YouTubeService(inventory: ToolLocator().scan())
    }

    private func transcript(for url: String, preferManual: Bool) async throws -> (VideoMetadata, CaptionTrack, Transcript) {
        let link = try #require(YouTubeLink(string: url))
        let service = try service()
        let metadata = try await service.fetchMetadata(for: link)
        let language = try #require(CaptionTrackSelector.defaultLanguage(for: metadata, preferred: "en"))
        let track = try #require(CaptionTrackSelector.track(for: metadata, languageCode: language, preferManual: preferManual))

        let data = try await TemporaryWorkspace.withDirectory { directory in
            try await service.downloadCaptions(track, for: link, into: directory)
        }
        let source: TranscriptSource = track.isAutomatic ? .autoCaptions : .manualCaptions
        let transcript = try CaptionParser.parse(json3: data, languageCode: track.languageCode, source: source)
        return (metadata, track, transcript)
    }

    @Test func manualCaptionsVideo() async throws {
        let (metadata, track, transcript) = try await transcript(for: Self.manualCaptionsVideo, preferManual: true)

        #expect(metadata.id == "iG9CE55wbtY")
        #expect(metadata.duration > 1000)
        #expect(!track.isAutomatic)
        #expect(transcript.source == .manualCaptions)
        #expect(transcript.wordCount > 2500)
        Self.expectWellFormed(transcript, duration: metadata.duration)
        Self.report(metadata, track, transcript)
    }

    @Test func autoCaptionsOnlyVideo() async throws {
        let (metadata, track, transcript) = try await transcript(for: Self.autoCaptionsVideo, preferManual: true)

        #expect(metadata.manualCaptions.isEmpty)
        #expect(track.isAutomatic)
        #expect(track.key == "en-orig")
        #expect(transcript.source == .autoCaptions)
        #expect(transcript.wordCount > 400)
        Self.expectWellFormed(transcript, duration: metadata.duration)
        Self.report(metadata, track, transcript)
    }

    @Test func longTranscriptExportsToAWellFormedPDF() async throws {
        let (metadata, _, transcript) = try await transcript(for: Self.manualCaptionsVideo, preferManual: true)
        var options = TranscriptOptions()
        options.timestampMode = .perParagraph
        let data = try PDFExporter.render(PDFExportInput(metadata: metadata, transcript: transcript, options: options))
        let document = try #require(PDFDocument(data: data))

        // ~3,100 words should run to roughly 7–12 pages.
        #expect((6...14).contains(document.pageCount), "\(document.pageCount) pages")
        let last = try #require(document.page(at: document.pageCount - 1)?.string)
        #expect(last.contains("Page \(document.pageCount) of \(document.pageCount)"))

        let links = (0..<document.pageCount).flatMap { document.page(at: $0)?.annotations ?? [] }
            .compactMap(\.url).filter { $0.absoluteString.contains("&t=") }
        #expect(links.count == transcript.paragraphs.count)
    }

    @Test func autoCaptionsOfManualVideoMatchInLength() async throws {
        // The TED talk also has speech-recognition captions. Deduplication must not lose or
        // double words, so both versions should land within 15% of each other.
        let (_, _, manual) = try await transcript(for: Self.manualCaptionsVideo, preferManual: true)
        let (_, autoTrack, auto) = try await transcript(for: Self.manualCaptionsVideo, preferManual: false)

        #expect(autoTrack.isAutomatic)
        let ratio = Double(auto.wordCount) / Double(manual.wordCount)
        #expect((0.85...1.15).contains(ratio), "auto/manual word ratio \(ratio)")
    }

    @Test func unavailableVideoIsReportedClearly() async throws {
        let link = try #require(YouTubeLink(videoID: "aaaaaaaaaaa"))
        await #expect(throws: YouTubeError.unavailable) {
            try await service().fetchMetadata(for: link)
        }
    }

    // MARK: - Whisper fallback

    private func pipelineWithBaseModel() async throws -> TranscriptPipeline {
        let pipeline = try TranscriptPipeline(inventory: ToolLocator().scan())
        if !pipeline.models.isInstalled(.base) {
            try await pipeline.models.download(.base)
        }
        return pipeline
    }

    /// Runs the pipeline, recording each step once and every reported fraction.
    private func run(_ pipeline: TranscriptPipeline, _ metadata: VideoMetadata) async throws(PipelineError)
        -> (Transcript, [TranscriptPipeline.Step], [TranscriptPipeline.Step: [Double]]) {
        let log = Mutex<([TranscriptPipeline.Step], [TranscriptPipeline.Step: [Double]])>(([], [:]))
        let transcript = try await pipeline.transcribe(.init(metadata: metadata)) { progress in
            log.withLock { log in
                if log.0.last != progress.step { log.0.append(progress.step) }
                if let fraction = progress.fraction { log.1[progress.step, default: []].append(fraction) }
            }
        }
        let (steps, fractions) = log.withLock { $0 }
        return (transcript, steps, fractions)
    }

    @Test func noCaptionsVideoIsTranscribedLocally() async throws {
        let pipeline = try await pipelineWithBaseModel()
        let link = try #require(YouTubeLink(string: Self.noCaptionsVideo))
        let metadata = try await pipeline.fetchMetadata(for: link)
        #expect(!metadata.hasCaptions)

        let (transcript, steps, fractions) = try await run(pipeline, metadata)

        #expect(steps == [.downloadingAudio, .transcribing, .formatting])
        for (step, values) in fractions {
            #expect(zip(values, values.dropFirst()).allSatisfy { $0 <= $1 }, "\(step) progress went backwards")
        }
        #expect((fractions[.transcribing]?.last ?? 0) >= 0.99)
        #expect(transcript.source == .whisper)
        #expect(transcript.languageCode == "hr")
        #expect(transcript.wordCount > 60)
        Self.expectWellFormed(transcript, duration: metadata.duration)

        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: TemporaryWorkspace.root.path)) ?? []
        #expect(leftovers.isEmpty, "temporary files were not cleaned up")
        Self.report(metadata, CaptionTrack(key: "whisper", languageCode: transcript.languageCode, name: "Whisper base", isAutomatic: true), transcript)
    }

    @Test func musicOnlyVideoProducesLittleOrNothing() async throws {
        let pipeline = try await pipelineWithBaseModel()
        let link = try #require(YouTubeLink(string: Self.musicOnlyVideo))
        let metadata = try await pipeline.fetchMetadata(for: link)

        do {
            let (transcript, _, _) = try await run(pipeline, metadata)
            #expect(transcript.wordCount < 80, "a music video shouldn't produce a long transcript")
        } catch {
            #expect(error == .whisper(.noSpeechDetected))
        }
    }

    @Test func pipelinePrefersCaptionsOverWhisper() async throws {
        let pipeline = try TranscriptPipeline(inventory: ToolLocator().scan())
        let link = try #require(YouTubeLink(string: Self.autoCaptionsVideo))
        let metadata = try await pipeline.fetchMetadata(for: link)

        let (transcript, steps, _) = try await run(pipeline, metadata)
        #expect(steps == [.downloadingCaptions, .formatting])
        #expect(transcript.source == .autoCaptions)
    }

    // MARK: - Helpers

    private static func expectWellFormed(_ transcript: Transcript, duration: TimeInterval) {
        let words = transcript.words
        let sentences = transcript.paragraphs.flatMap(\.sentences)

        #expect(zip(words, words.dropFirst()).allSatisfy { $0.start <= $1.start + 0.001 }, "word times go backwards")
        #expect(words.allSatisfy { $0.end >= $0.start && $0.start >= 0 && $0.start <= duration + 5 })
        #expect(words.allSatisfy { !$0.text.contains("[") && !$0.text.contains(">>") }, "annotation leaked into text")
        #expect(sentences.allSatisfy { TranscriptAssembler.endsSentence($0.words.last?.text ?? "") || $0.words.count < 100 })
        #expect(sentences.allSatisfy { $0.text.first?.isLowercase != true }, "sentence starts lowercase")
        #expect(transcript.paragraphs.allSatisfy { $0.sentences.reduce(0) { $0 + $1.words.count } <= 140 })

        // No word should appear twice in a row with the same timestamp: that is a dedup miss.
        let doubled = zip(words, words.dropFirst()).filter { $0.text.lowercased() == $1.text.lowercased() && abs($0.start - $1.start) < 0.05 }
        #expect(doubled.isEmpty, "duplicated words: \(doubled.count)")
    }

    /// Renders the video's fingerprint (band and slim header) when `YTTOPDF_RENDER_DIR` is set.
    private static func renderFingerprint(_ metadata: VideoMetadata, _ transcript: Transcript) {
        guard let path = ProcessInfo.processInfo.environment["YTTOPDF_RENDER_DIR"] else { return }
        let directory = URL(filePath: path)
        let fingerprint = SpeechFingerprint(transcript: transcript, duration: metadata.duration, videoID: metadata.id)
        let accent = CGColor(srgbRed: 0.16, green: 0.33, blue: 0.85, alpha: 1)
        let paper = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
        var header = FingerprintRenderer.Style(color: accent)
        header.highlight = (metadata.duration * 0.3)...(metadata.duration * 0.45)
        try? FingerprintTests.writePNG(
            FingerprintRenderer.image(fingerprint, size: CGSize(width: 480, height: 51), scale: 3, style: .init(color: accent), background: paper),
            to: directory, name: "real-\(metadata.id)-band")
        try? FingerprintTests.writePNG(
            FingerprintRenderer.image(fingerprint, size: CGSize(width: 150, height: 11), scale: 6, style: header, background: paper),
            to: directory, name: "real-\(metadata.id)-header")
    }

    private static func report(_ metadata: VideoMetadata, _ track: CaptionTrack, _ transcript: Transcript) {
        renderFingerprint(metadata, transcript)
        let sentences = transcript.paragraphs.flatMap(\.sentences)
        let averageSentence = Double(transcript.words.count) / Double(max(sentences.count, 1))
        let averageParagraph = Double(transcript.words.count) / Double(max(transcript.paragraphs.count, 1))
        let line = """
        [RealVideo] \(metadata.id) track=\(track.id) words=\(transcript.wordCount) \
        sentences=\(sentences.count) (avg \(String(format: "%.1f", averageSentence)) words) \
        paragraphs=\(transcript.paragraphs.count) (avg \(String(format: "%.1f", averageParagraph)) words) \
        languages=\(CaptionTrackSelector.languageOptions(for: metadata).count)

        """
        // Test output doesn't reach xcodebuild's console, so stats go to a file when asked.
        guard let path = ProcessInfo.processInfo.environment["YTTOPDF_REPORT_PATH"] else { return }
        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: URL(filePath: path))
        }
    }
}
