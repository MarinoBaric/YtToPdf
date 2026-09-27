import Synchronization

/// Forwards progress values only when they move forward, from any thread.
nonisolated final class MonotonicProgress: Sendable {
    private let latest = Mutex(-1.0)
    private let report: @Sendable (Double) -> Void

    init(report: @escaping @Sendable (Double) -> Void) {
        self.report = report
    }

    func update(_ fraction: Double) {
        let advanced = latest.withLock { latest in
            guard fraction > latest else { return false }
            latest = fraction
            return true
        }
        if advanced { report(fraction) }
    }
}
