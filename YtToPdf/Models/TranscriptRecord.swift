import Foundation
import SwiftData

/// A saved transcript in the history sidebar. Holds everything needed to reopen
/// and re-export it without downloading anything again.
@Model
final class TranscriptRecord {
    var videoID: String
    var title: String
    var channel: String
    var webpageURL: URL
    var durationSeconds: Double
    var uploadDate: Date?
    var thumbnailURL: URL?
    @Attribute(.externalStorage) var thumbnailData: Data?
    var languageCode: String
    var sourceRawValue: String
    var wordCount: Int
    /// Flattened transcript text, kept so history search can match the body.
    var plainText: String
    @Attribute(.externalStorage) var transcriptData: Data
    /// The full `VideoMetadata`, including caption tracks, so the video card reopens offline.
    @Attribute(.externalStorage) var metadataData = Data()
    /// The options last used for this transcript (timestamps, export toggles).
    var optionsData: Data?
    var createdAt: Date

    init(metadata: VideoMetadata, transcript: Transcript, thumbnailData: Data?, options: TranscriptOptions = TranscriptOptions(), createdAt: Date = .now) throws {
        videoID = metadata.id
        title = metadata.title
        channel = metadata.channel
        webpageURL = metadata.webpageURL
        durationSeconds = metadata.duration
        uploadDate = metadata.uploadDate
        thumbnailURL = metadata.thumbnailURL
        self.thumbnailData = thumbnailData
        languageCode = transcript.languageCode
        sourceRawValue = transcript.source.rawValue
        wordCount = transcript.wordCount
        plainText = transcript.plainText
        transcriptData = try JSONEncoder().encode(transcript)
        metadataData = try JSONEncoder().encode(metadata)
        optionsData = try JSONEncoder().encode(options)
        self.createdAt = createdAt
    }

    /// Replaces the contents with a fresh generation of the same video and language.
    func update(metadata: VideoMetadata, transcript: Transcript, thumbnailData: Data?, options: TranscriptOptions, at date: Date = .now) throws {
        title = metadata.title
        channel = metadata.channel
        webpageURL = metadata.webpageURL
        durationSeconds = metadata.duration
        uploadDate = metadata.uploadDate
        thumbnailURL = metadata.thumbnailURL
        if let thumbnailData { self.thumbnailData = thumbnailData }
        sourceRawValue = transcript.source.rawValue
        wordCount = transcript.wordCount
        plainText = transcript.plainText
        transcriptData = try JSONEncoder().encode(transcript)
        metadataData = try JSONEncoder().encode(metadata)
        optionsData = try JSONEncoder().encode(options)
        createdAt = date
    }

    var source: TranscriptSource? {
        TranscriptSource(rawValue: sourceRawValue)
    }

    func decodedTranscript() throws -> Transcript {
        try JSONDecoder().decode(Transcript.self, from: transcriptData)
    }

    /// The stored metadata, or one rebuilt from the plain fields for records saved without it.
    func decodedMetadata() -> VideoMetadata {
        if let metadata = try? JSONDecoder().decode(VideoMetadata.self, from: metadataData) {
            return metadata
        }
        return VideoMetadata(
            id: videoID, title: title, channel: channel, duration: durationSeconds,
            uploadDate: uploadDate, thumbnailURL: thumbnailURL, webpageURL: webpageURL,
            languageCode: languageCode, manualCaptions: [], automaticCaptions: []
        )
    }

    func decodedOptions() -> TranscriptOptions? {
        optionsData.flatMap { try? JSONDecoder().decode(TranscriptOptions.self, from: $0) }
    }
}
