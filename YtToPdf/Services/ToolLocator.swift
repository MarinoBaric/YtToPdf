import Foundation

/// Finds the Homebrew-installed tools YtToPdf depends on.
///
/// Apps launched from Finder don't inherit the shell's `PATH`, so this looks in
/// Homebrew's fixed install locations instead.
nonisolated struct ToolLocator: Sendable {
    static let defaultSearchDirectories = [
        URL(filePath: "/opt/homebrew/bin", directoryHint: .isDirectory),
        URL(filePath: "/usr/local/bin", directoryHint: .isDirectory),
    ]

    var searchDirectories: [URL]

    init(searchDirectories: [URL] = ToolLocator.defaultSearchDirectories) {
        self.searchDirectories = searchDirectories
    }

    func scan() -> ToolInventory {
        var locations: [ExternalTool: URL] = [:]
        for tool in ExternalTool.allCases {
            locations[tool] = locate(tool)
        }
        return ToolInventory(locations: locations, homebrewURL: firstExecutable(named: "brew"))
    }

    func locate(_ tool: ExternalTool) -> URL? {
        for name in tool.executableNames {
            if let url = firstExecutable(named: name) { return url }
        }
        return nil
    }

    private func firstExecutable(named name: String) -> URL? {
        searchDirectories
            .map { $0.appending(path: name, directoryHint: .notDirectory) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path(percentEncoded: false)) }
    }
}
