import Foundation

/// How densely words are spoken across a video: the data behind the Speech Fingerprint.
///
/// The video is cut into equal time slices and the words starting in each are counted. The
/// variation derived from the video ID makes every fingerprint's rhythm its own, but always the
/// same for the same video.
nonisolated struct SpeechFingerprint: Sendable, Hashable {
    static let defaultSliceCount = 120

    /// Words that start in each slice.
    let wordCounts: [Int]
    /// Bar heights in 0...1. Zero only for silent slices.
    let densities: [Double]
    let duration: TimeInterval
    let variation: FingerprintVariation

    var sliceCount: Int { wordCounts.count }
    var sliceDuration: TimeInterval { duration / Double(max(sliceCount, 1)) }

    init(transcript: Transcript, duration: TimeInterval, videoID: String, sliceCount: Int = defaultSliceCount) {
        let words = transcript.words
        let length = duration > 0 ? duration : (words.last?.end ?? 0)
        self.init(wordStarts: words.map(\.start), duration: length, seed: FingerprintSeed.value(for: videoID), sliceCount: sliceCount)
    }

    init(wordStarts: [TimeInterval], duration: TimeInterval, seed: UInt64, sliceCount: Int = defaultSliceCount) {
        let slices = max(sliceCount, 1)
        var counts = Array(repeating: 0, count: slices)
        if duration > 0 {
            for start in wordStarts where start >= 0 {
                let index = min(slices - 1, Int(start / duration * Double(slices)))
                counts[index] += 1
            }
        }
        wordCounts = counts
        densities = Self.normalize(counts)
        self.duration = max(duration, 0)
        variation = FingerprintVariation(seed: seed)
    }

    /// Scales counts to 0...1 against the busiest slice. A gentle curve lifts quiet stretches so
    /// they stay readable next to rapid speech; any spoken slice gets at least a short bar.
    private static func normalize(_ counts: [Int]) -> [Double] {
        guard let peak = counts.max(), peak > 0 else { return counts.map { _ in 0 } }
        return counts.map { count in
            count == 0 ? 0 : max(0.14, pow(Double(count) / Double(peak), 0.8))
        }
    }

    /// The slices that overlap a time range, e.g. the stretch of video a PDF page covers.
    func slices(overlapping range: ClosedRange<TimeInterval>) -> ClosedRange<Int>? {
        guard duration > 0, range.upperBound >= 0, range.lowerBound <= duration else { return nil }
        let first = max(0, Int(range.lowerBound / sliceDuration))
        let last = min(sliceCount - 1, Int(range.upperBound / sliceDuration))
        return first <= last ? first...last : nil
    }
}

/// Small, deterministic differences between fingerprints, derived from the video ID.
nonisolated struct FingerprintVariation: Sendable, Hashable {
    /// How far bar spacing swings from perfectly even, as a fraction of the pitch.
    let rhythmAmplitude: Double
    /// Bars per spacing cycle.
    let rhythmPeriod: Double
    let rhythmPhase: Double
    /// Tilt of the left-to-right opacity gradient, in radians.
    let gradientAngle: Double
    /// Bar width as a fraction of the pitch between bars.
    let barWidthRatio: Double

    init(seed: UInt64) {
        var random = SplitMix64(seed: seed)
        rhythmAmplitude = random.next(in: 0.04...0.16)
        rhythmPeriod = random.next(in: 5...13)
        rhythmPhase = random.next(in: 0...(2 * .pi))
        gradientAngle = random.next(in: -0.17...0.17)
        barWidthRatio = random.next(in: 0.44...0.56)
    }
}

/// Turns a video ID into a stable 64-bit seed. Swift's `Hasher` is randomised per launch, so
/// this uses FNV-1a, which gives the same value everywhere, forever.
nonisolated enum FingerprintSeed {
    static func value(for videoID: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in videoID.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }
}

/// A small, fast, deterministic random number generator (SplitMix64).
nonisolated struct SplitMix64: RandomNumberGenerator, Sendable {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9e37_79b9_7f4a_7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58_476d_1ce4_e5b9
        z = (z ^ (z >> 27)) &* 0x94d0_49bb_1331_11eb
        return z ^ (z >> 31)
    }

    mutating func next(in range: ClosedRange<Double>) -> Double {
        let unit = Double(next() >> 11) / Double(1 << 53)
        return range.lowerBound + unit * (range.upperBound - range.lowerBound)
    }
}
