import AppKit
import Observation

/// Notices when the clipboard holds a web link, without reading it.
///
/// macOS asks the user before an app reads the clipboard programmatically. Pattern detection
/// only reports *that* a URL is there, so it never triggers that alert; the actual paste goes
/// through the system `PasteButton`, which the user drives.
@Observable
final class ClipboardWatcher {
    private(set) var hasLink = false
    private var lastChangeCount = -1

    func refresh() async {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        let patterns = try? await pasteboard.detectedPatterns(for: [\.probableWebURL])
        hasLink = patterns?.contains(\.probableWebURL) == true
    }
}
