import Foundation

/// Renders a transcript as plain text, used for Copy All and the TXT export.
nonisolated enum PlainTextRenderer {
    static func render(_ transcript: Transcript, metadata: VideoMetadata?, options: TranscriptOptions) -> String {
        var output = ""
        if options.includeVideoInfo, let metadata {
            output += header(for: metadata, transcript: transcript) + "\n\n"
        }

        let blocks = TranscriptLayout.blocks(for: transcript, mode: options.timestampMode)
        for (index, block) in blocks.enumerated() {
            if index > 0 { output += block.startsParagraph ? "\n\n" : "\n" }
            if let timestamp = block.timestamp {
                output += TimeFormatting.timestamp(timestamp, style: options.timestampStyle) + " "
            }
            output += block.text
        }
        return output + "\n"
    }

    static func header(for metadata: VideoMetadata, transcript: Transcript) -> String {
        var details = [metadata.channel]
        if let date = metadata.uploadDate { details.append(TimeFormatting.uploadDate(date)) }
        details.append(TimeFormatting.duration(metadata.duration))
        details.append("\(transcript.wordCount.formatted()) words")
        return [metadata.title, details.joined(separator: " · "), metadata.webpageURL.absoluteString].joined(separator: "\n")
    }
}
