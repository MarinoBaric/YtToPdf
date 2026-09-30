import Foundation

/// Renders a transcript as Markdown: a heading and details, then paragraphs with timestamps
/// that link to that moment in the video.
nonisolated enum MarkdownRenderer {
    static func render(_ transcript: Transcript, metadata: VideoMetadata, options: TranscriptOptions) -> String {
        var output = ""
        if options.includeVideoInfo {
            output += header(for: metadata, transcript: transcript) + "\n\n---\n\n"
        }

        let link = YouTubeLink(videoID: metadata.id)
        let blocks = TranscriptLayout.blocks(for: transcript, mode: options.timestampMode)
        for (index, block) in blocks.enumerated() {
            if index > 0 { output += block.startsParagraph ? "\n\n" : "  \n" }
            if let time = block.timestamp {
                let label = escape(TimeFormatting.timestamp(time, style: options.timestampStyle))
                if options.clickableTimestamps, let link {
                    output += "**[\(label)](\(link.watchURL(at: time).absoluteString))** "
                } else {
                    output += "**\(label)** "
                }
            }
            output += escape(block.text)
        }
        return output + "\n"
    }

    private static func header(for metadata: VideoMetadata, transcript: Transcript) -> String {
        var details = ["**\(escape(metadata.channel))**"]
        if let date = metadata.uploadDate { details.append("Uploaded \(TimeFormatting.uploadDate(date))") }
        details.append(TimeFormatting.duration(metadata.duration))
        details.append("\(transcript.wordCount.formatted()) words")

        let language = Locale.current.localizedString(forLanguageCode: transcript.languageCode) ?? transcript.languageCode
        let source = "\(transcript.source.label) (\(language)) · [youtu.be/\(metadata.id)](\(metadata.webpageURL.absoluteString))"
        return "# \(escape(metadata.title))\n\n\(details.joined(separator: " · "))  \n\(source)"
    }

    /// Backslash-escapes characters Markdown would otherwise read as formatting.
    static func escape(_ text: String) -> String {
        var escaped = ""
        for character in text {
            if "\\`*_[]<>#|".contains(character) { escaped.append("\\") }
            escaped.append(character)
        }
        return escaped
    }
}
