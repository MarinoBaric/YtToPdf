import Foundation

/// Fetches a video thumbnail so it can be shown now and stored with the history entry.
nonisolated enum ThumbnailLoader {
    @concurrent
    static func load(_ url: URL?) async -> Data? {
        guard let url else { return nil }
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              !data.isEmpty
        else { return nil }
        return data
    }
}
