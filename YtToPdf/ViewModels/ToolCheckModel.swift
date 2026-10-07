import Foundation
import Observation

/// Tracks whether the external tools are installed, re-checking on demand.
@Observable
final class ToolCheckModel {
    enum State: Equatable {
        case checking
        case ready(ToolInventory)
        case missing(ToolInventory)
    }

    private(set) var state: State = .checking
    private let locator: ToolLocator

    init(locator: ToolLocator = ToolLocator()) {
        self.locator = locator
    }

    func refresh() async {
        let inventory = await Self.scan(with: locator)
        state = inventory.isComplete ? .ready(inventory) : .missing(inventory)
    }

    @concurrent
    private nonisolated static func scan(with locator: ToolLocator) async -> ToolInventory {
        locator.scan()
    }
}
