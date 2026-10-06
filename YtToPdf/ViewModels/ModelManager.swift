import Foundation
import Observation

/// Whisper model downloads and deletions for the Settings window.
@Observable
final class ModelManager {
    enum State: Equatable {
        case notInstalled
        case downloading(Double)
        case installed(bytes: Int64)
        case failed(String)
    }

    private(set) var states: [WhisperModel: State] = [:]
    let store: WhisperModelStore
    private var downloads: [WhisperModel: Task<Void, Never>] = [:]

    init(store: WhisperModelStore = WhisperModelStore()) {
        self.store = store
        refresh()
    }

    func state(of model: WhisperModel) -> State {
        states[model] ?? .notInstalled
    }

    /// Re-reads what's on disk, leaving downloads in progress alone.
    func refresh() {
        for model in WhisperModel.allCases where downloads[model] == nil {
            states[model] = installedState(of: model)
        }
    }

    func download(_ model: WhisperModel) {
        guard downloads[model] == nil else { return }
        states[model] = .downloading(0)

        let (updates, continuation) = AsyncStream.makeStream(of: Double.self, bufferingPolicy: .bufferingNewest(1))
        downloads[model] = Task {
            // Cancelled in the `defer` below, so capturing `self` strongly can't leak.
            let listener = Task {
                for await fraction in updates where downloads[model] != nil {
                    states[model] = .downloading(fraction)
                }
            }
            defer {
                continuation.finish()
                listener.cancel()
                downloads[model] = nil
            }
            do throws(WhisperError) {
                try await store.download(model) { continuation.yield($0) }
                states[model] = installedState(of: model)
            } catch .cancelled {
                states[model] = .notInstalled
            } catch {
                states[model] = .failed(error.recoverySuggestion ?? error.localizedDescription)
            }
        }
    }

    func cancelDownload(_ model: WhisperModel) {
        downloads[model]?.cancel()
    }

    func delete(_ model: WhisperModel) throws {
        try store.delete(model)
        states[model] = .notInstalled
    }

    private func installedState(of model: WhisperModel) -> State {
        guard store.isInstalled(model) else { return .notInstalled }
        let path = store.url(for: model).path(percentEncoded: false)
        let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber)?.int64Value ?? model.approximateBytes
        return .installed(bytes: size)
    }
}
