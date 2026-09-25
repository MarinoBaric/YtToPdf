import Foundation

/// Everything that can go wrong talking to YouTube through yt-dlp.
nonisolated enum YouTubeError: Error, Equatable, Sendable {
    case invalidURL
    case unavailable
    case privateVideo
    case ageRestricted
    case membersOnly
    case liveOrUpcoming
    case botCheck
    case noNetwork
    case ytDlpOutdated
    case captionsUnavailable
    case malformedOutput(String)
    case toolFailed(String)
    case cancelled
}

extension YouTubeError: LocalizedError {
    static let updateCommand = "brew upgrade yt-dlp"

    var errorDescription: String? {
        switch self {
        case .invalidURL: "That doesn't look like a YouTube video link."
        case .unavailable: "This video is unavailable."
        case .privateVideo: "This video is private."
        case .ageRestricted: "This video is age-restricted."
        case .membersOnly: "This video is for channel members only."
        case .liveOrUpcoming: "This is a live stream or premiere that hasn't finished."
        case .botCheck: "YouTube is asking to confirm you're not a bot."
        case .noNetwork: "Can't reach YouTube."
        case .ytDlpOutdated: "yt-dlp needs an update."
        case .captionsUnavailable: "The captions for this video couldn't be downloaded."
        case .malformedOutput: "yt-dlp returned data YtToPdf couldn't read."
        case .toolFailed: "yt-dlp ran into a problem."
        case .cancelled: "Cancelled."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .invalidURL: "Paste a link like youtube.com/watch?v=…, youtu.be/… or youtube.com/shorts/…"
        case .unavailable: "It may have been removed, or it's blocked in your region."
        case .privateVideo: "Only people the owner has invited can watch it, so there's nothing to transcribe."
        case .ageRestricted: "YouTube requires a signed-in account for this video, which YtToPdf doesn't use."
        case .membersOnly: "YouTube requires a signed-in member account for this video."
        case .liveOrUpcoming: "Try again once the stream has ended and YouTube has processed it."
        case .botCheck: "Wait a few minutes and try again. Updating yt-dlp often helps too."
        case .noNetwork: "Check your internet connection and try again."
        case .ytDlpOutdated: "YouTube changes often. Run this in Terminal, then try again:"
        case .captionsUnavailable: "Try another language, or turn off “Prefer manual captions”."
        case .malformedOutput(let detail), .toolFailed(let detail): detail
        case .cancelled: nil
        }
    }

    /// A Terminal command that fixes the problem, when there is one.
    var fixCommand: String? {
        switch self {
        case .ytDlpOutdated, .botCheck: Self.updateCommand
        default: nil
        }
    }
}
