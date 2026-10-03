import Foundation

/// Any failure while producing a transcript, grouped by where it came from.
nonisolated enum PipelineError: Error, Equatable, Sendable {
    case tools(ToolError)
    case youTube(YouTubeError)
    case captions(CaptionParserError)
    case whisper(WhisperError)
    case export(PDFExportError)

    var isCancellation: Bool {
        self == .youTube(.cancelled) || self == .whisper(.cancelled)
    }

    private var underlying: any LocalizedError {
        switch self {
        case .tools(let error): error
        case .youTube(let error): error
        case .captions(let error): error
        case .whisper(let error): error
        case .export(let error): error
        }
    }
}

extension PipelineError: LocalizedError {
    var errorDescription: String? { underlying.errorDescription }
    var recoverySuggestion: String? { underlying.recoverySuggestion }

    var fixCommand: String? {
        switch self {
        case .youTube(let error): error.fixCommand
        case .tools(.missing(let tool)): "brew install \(tool.brewFormula)"
        default: nil
        }
    }
}

extension ToolError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .missing(let tool): "\(tool.displayName) isn't installed."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .missing: "Install it with Homebrew, then try again:"
        }
    }
}
