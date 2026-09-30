import Foundation

nonisolated enum TimeFormatting {
    /// `[03:07]` or `[00:03:07]`. Minutes keep counting past an hour in `mm:ss` style (`[75:12]`).
    static func timestamp(_ seconds: TimeInterval, style: TranscriptOptions.TimestampStyle, brackets: Bool = true) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let body = switch style {
        case .minutesSeconds:
            String(format: "%02d:%02d", total / 60, total % 60)
        case .hoursMinutesSeconds:
            String(format: "%02d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
        }
        return brackets ? "[\(body)]" : body
    }

    /// A video length for display: `4:05`, `12:34`, `1:02:03`.
    static func duration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600, minutes = total / 60 % 60, secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }

    /// The upload date in the reader's locale, e.g. "15 Mar 2024". Upload dates are calendar
    /// days, so format them in UTC to avoid shifting by a day.
    static func uploadDate(_ date: Date) -> String {
        var style = Date.FormatStyle(date: .abbreviated, time: .omitted)
        style.timeZone = .gmt
        return date.formatted(style)
    }
}
