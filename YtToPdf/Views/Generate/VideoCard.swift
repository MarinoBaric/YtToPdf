import AppKit
import SwiftUI

struct VideoCard: View {
    let metadata: VideoMetadata
    let thumbnail: Data?
    /// The transcript's source once generated; before that the card shows what's available.
    var source: TranscriptSource?
    /// Shown along the bottom of the card once there's a transcript.
    var fingerprint: SpeechFingerprint?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            details
            if let fingerprint {
                Divider()
                SpeechFingerprintView(fingerprint: fingerprint)
                    .frame(height: 64)
                    .id(metadata.id)
                    .transition(.opacity)
            }
        }
        .surface(padding: 16)
        .animation(.smooth, value: fingerprint == nil)
    }

    private var details: some View {
        HStack(alignment: .top, spacing: 20) {
            VideoThumbnail(data: thumbnail, duration: metadata.duration)
                .frame(width: 208)

            VStack(alignment: .leading, spacing: 6) {
                Text(metadata.title)
                    .font(.title3.weight(.semibold))
                    .lineLimit(3)
                    .textSelection(.enabled)
                Text(metadata.channel)
                    .foregroundStyle(.secondary)

                HStack(spacing: 14) {
                    Label(TimeFormatting.duration(metadata.duration), systemImage: "clock")
                    if let date = metadata.uploadDate {
                        Label(TimeFormatting.uploadDate(date), systemImage: "calendar")
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.top, 2)

                CaptionBadge(metadata: metadata, source: source)
                    .padding(.top, 6)
            }
            Spacer(minLength: 0)
        }
    }
}

struct VideoThumbnail: View {
    let data: Data?
    let duration: TimeInterval

    var body: some View {
        Color.secondary.opacity(0.12)
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay {
                if let data, let image = NSImage(data: data) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .transition(.opacity)
                } else {
                    Image(systemName: "play.rectangle")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                Text(TimeFormatting.duration(duration))
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.7), in: .rect(cornerRadius: 4))
                    .padding(6)
            }
            .clipShape(.rect(cornerRadius: 12))
    }
}

/// Says where the words will come from: manual captions, auto captions or local Whisper.
struct CaptionBadge: View {
    let metadata: VideoMetadata
    let source: TranscriptSource?

    private var content: (String, String) {
        switch source {
        case .manualCaptions: ("Manual captions", "captions.bubble.fill")
        case .autoCaptions: ("Auto-generated captions", "captions.bubble")
        case .whisper: ("Transcribed on your Mac", "waveform")
        case nil:
            if !metadata.manualCaptions.isEmpty { ("Manual captions available", "captions.bubble.fill") }
            else if !metadata.automaticCaptions.isEmpty { ("Auto-generated captions available", "captions.bubble") }
            else { ("No captions · will transcribe on your Mac", "waveform") }
        }
    }

    var body: some View {
        Label(content.0, systemImage: content.1)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.quaternary.opacity(0.6), in: .capsule)
    }
}

/// Shown while video info loads.
struct VideoCardPlaceholder: View {
    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            RoundedRectangle(cornerRadius: 12)
                .fill(.quaternary)
                .aspectRatio(16 / 9, contentMode: .fit)
                .frame(width: 208)
            VStack(alignment: .leading, spacing: 10) {
                Text("Loading video title placeholder")
                    .font(.title3.weight(.semibold))
                Text("Channel name")
                Text("12:34 · 1 Jan 2024")
                    .font(.callout)
            }
            .redacted(reason: .placeholder)
            Spacer(minLength: 0)
        }
        .surface(padding: 16)
        .phaseAnimator([0.55, 1]) { content, opacity in
            content.opacity(opacity)
        } animation: { _ in .easeInOut(duration: 0.9) }
        .accessibilityLabel("Loading video info")
    }
}
