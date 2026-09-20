import Foundation

nonisolated enum ToolError: Error, Equatable, Sendable {
    case missing(ExternalTool)
}

/// Where each external tool was found on this Mac.
nonisolated struct ToolInventory: Sendable, Equatable {
    static let homebrewInstallCommand =
        #"/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)""#

    static let empty = ToolInventory(locations: [:], homebrewURL: nil)

    var locations: [ExternalTool: URL]
    var homebrewURL: URL?

    var missingTools: [ExternalTool] {
        ExternalTool.allCases.filter { locations[$0] == nil }
    }

    var isComplete: Bool { missingTools.isEmpty }

    /// The exact command that installs everything still missing, or `nil` when nothing is.
    var installCommand: String? {
        guard !missingTools.isEmpty else { return nil }
        return "brew install " + missingTools.map(\.brewFormula).joined(separator: " ")
    }

    func url(for tool: ExternalTool) throws(ToolError) -> URL {
        guard let url = locations[tool] else { throw .missing(tool) }
        return url
    }
}
