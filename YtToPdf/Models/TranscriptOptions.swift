import Foundation

/// How a transcript is generated and laid out. Defaults come from Settings; the options panel
/// changes them for the current transcript only.
nonisolated struct TranscriptOptions: Codable, Sendable, Hashable {
    enum TimestampMode: String, Codable, CaseIterable, Identifiable, Sendable {
        case off
        case perParagraph
        case every15
        case every30
        case every60

        var id: String { rawValue }

        var interval: TimeInterval? {
            switch self {
            case .off, .perParagraph: nil
            case .every15: 15
            case .every30: 30
            case .every60: 60
            }
        }

        var label: String {
            switch self {
            case .off: "Off"
            case .perParagraph: "Paragraph"
            case .every15: "15 s"
            case .every30: "30 s"
            case .every60: "60 s"
            }
        }
    }

    enum TimestampStyle: String, Codable, CaseIterable, Identifiable, Sendable {
        case minutesSeconds
        case hoursMinutesSeconds

        var id: String { rawValue }

        var label: String {
            switch self {
            case .minutesSeconds: "[mm:ss]"
            case .hoursMinutesSeconds: "[hh:mm:ss]"
            }
        }
    }

    var timestampMode = TimestampMode.perParagraph
    var timestampStyle = TimestampStyle.minutesSeconds
    var preferManualCaptions = true
    var includeVideoInfo = true
    var clickableTimestamps = true
    var whisperModel = WhisperModel.default
}

/// The default options, kept in user defaults and edited in Settings.
nonisolated enum DefaultOptions {
    private static let key = "defaultTranscriptOptions"

    static func load(from defaults: UserDefaults = .standard) -> TranscriptOptions {
        guard let data = defaults.data(forKey: key),
              let options = try? JSONDecoder().decode(TranscriptOptions.self, from: data)
        else { return TranscriptOptions() }
        return options
    }

    static func save(_ options: TranscriptOptions, to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(options) else { return }
        defaults.set(data, forKey: key)
    }
}
