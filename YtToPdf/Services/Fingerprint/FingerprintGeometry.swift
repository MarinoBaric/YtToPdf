import CoreGraphics
import Foundation

/// Where each bar or dot of a Speech Fingerprint goes inside a rectangle.
///
/// Pure layout, shared by the app (SwiftUI `Canvas`) and the PDF (Core Graphics), so both draw
/// exactly the same shape.
nonisolated enum FingerprintGeometry {
    struct Mark: Sendable, Equatable {
        let index: Int
        /// A rounded bar centred on the horizontal axis, or a small circle for a silent slice.
        let rect: CGRect
        let isDot: Bool
    }

    /// - Parameter growth: 0...1 for the entrance animation. Bars rise from the axis in a wave
    ///   running left to right; 1 is the finished shape.
    static func marks(for fingerprint: SpeechFingerprint, in rect: CGRect, growth: Double = 1) -> [Mark] {
        let count = fingerprint.sliceCount
        guard count > 0, rect.width > 0, rect.height > 0 else { return [] }

        let variation = fingerprint.variation
        let pitches = spacing(count: count, totalWidth: rect.width, variation: variation)
        let basePitch = rect.width / Double(count)
        let barWidth = max(0.35, basePitch * variation.barWidthRatio)
        let dotSize = min(barWidth * 1.15, rect.height * 0.3)
        let minBarHeight = min(rect.height, max(barWidth * 2.4, dotSize * 1.8))

        var marks: [Mark] = []
        marks.reserveCapacity(count)
        var cursor = rect.minX
        for index in 0..<count {
            let centerX = cursor + pitches[index] / 2
            cursor += pitches[index]

            let density = fingerprint.densities[index]
            let rise = growthFactor(index: index, count: count, growth: growth)
            if density == 0 {
                let size = dotSize * min(1, rise * 1.5)
                marks.append(Mark(
                    index: index,
                    rect: CGRect(x: centerX - size / 2, y: rect.midY - size / 2, width: size, height: size),
                    isDot: true
                ))
            } else {
                let fullHeight = max(minBarHeight, density * rect.height)
                let height = max(barWidth * rise, fullHeight * rise)
                marks.append(Mark(
                    index: index,
                    rect: CGRect(x: centerX - barWidth / 2, y: rect.midY - height / 2, width: barWidth, height: height),
                    isDot: false
                ))
            }
        }
        return marks
    }

    /// Near-even spacing with a gentle seeded swing, scaled so the pitches fill `totalWidth`.
    static func spacing(count: Int, totalWidth: Double, variation: FingerprintVariation) -> [Double] {
        let weights = (0..<count).map { index in
            1 + variation.rhythmAmplitude * sin(2 * .pi * Double(index) / variation.rhythmPeriod + variation.rhythmPhase)
        }
        let total = weights.reduce(0, +)
        return weights.map { $0 / total * totalWidth }
    }

    private static func growthFactor(index: Int, count: Int, growth: Double) -> Double {
        guard growth < 1 else { return 1 }
        let delay = 0.35 * Double(index) / Double(max(count - 1, 1))
        let local = (growth - delay) / 0.65
        let clamped = min(1, max(0, local))
        // Ease out so bars settle softly.
        return 1 - pow(1 - clamped, 3)
    }
}
