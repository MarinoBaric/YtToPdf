import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import YtToPdf

@Suite("Speech Fingerprint")
struct FingerprintTests {
    /// Steady speech with a silent stretch from 40 s to 60 s and a burst near the end.
    static let sampleStarts: [TimeInterval] = {
        var starts: [TimeInterval] = []
        var time = 0.0
        while time < 120 {
            if !(40..<60).contains(time) { starts.append(time) }
            time += (100..<110).contains(time) ? 0.15 : 0.4
        }
        return starts
    }()

    static let sample = SpeechFingerprint(wordStarts: sampleStarts, duration: 120, seed: FingerprintSeed.value(for: "abcdefghijk"))

    // MARK: - Data

    @Test func countsWordsPerSlice() {
        let fingerprint = SpeechFingerprint(wordStarts: [0, 0.5, 1.2, 5.9, 6, 11.99, 50], duration: 12, seed: 1, sliceCount: 4)
        // Slices of 3 s: [0,3) [3,6) [6,9) [9,12]; 50 s is past the end and lands in the last slice.
        #expect(fingerprint.wordCounts == [3, 1, 1, 2])
        #expect(fingerprint.densities.allSatisfy { $0 > 0 && $0 <= 1 })
        #expect(fingerprint.densities[0] == 1)
    }

    @Test func silentSlicesAreZeroAndQuietOnesStillVisible() {
        let fingerprint = Self.sample
        #expect(fingerprint.sliceCount == 120)
        let silent = (40..<60).map { fingerprint.densities[$0] }
        #expect(silent.allSatisfy { $0 == 0 })
        #expect(fingerprint.densities.filter { $0 > 0 }.allSatisfy { $0 >= 0.14 })
        let peak = fingerprint.densities.indices.max { fingerprint.densities[$0] < fingerprint.densities[$1] }
        #expect((100..<110).contains(peak ?? -1), "the burst is the busiest stretch")
    }

    @Test func emptyOrZeroLengthInputsDontCrash() {
        let empty = SpeechFingerprint(wordStarts: [], duration: 0, seed: 1)
        #expect(empty.densities.allSatisfy { $0 == 0 })
        #expect(empty.slices(overlapping: 0...10) == nil)
        let marks = FingerprintGeometry.marks(for: empty, in: CGRect(x: 0, y: 0, width: 300, height: 40))
        #expect(marks.allSatisfy { $0.isDot })
    }

    @Test func mapsTimeRangesToSlices() {
        let fingerprint = Self.sample // 1 s per slice
        #expect(fingerprint.slices(overlapping: 30...44.5) == 30...44)
        #expect(fingerprint.slices(overlapping: -5...0.5) == 0...0)
        #expect(fingerprint.slices(overlapping: 110...500) == 110...119)
        #expect(fingerprint.slices(overlapping: 130...140) == nil)
    }

    // MARK: - Seeding

    @Test func seedIsStableFNV1a() {
        // Published FNV-1a 64-bit test vectors.
        #expect(FingerprintSeed.value(for: "") == 0xcbf2_9ce4_8422_2325)
        #expect(FingerprintSeed.value(for: "a") == 0xaf63_dc4c_8601_ec8c)
    }

    @Test func sameVideoSameVariationDifferentVideoDifferentVariation() {
        let a1 = FingerprintVariation(seed: FingerprintSeed.value(for: "iG9CE55wbtY"))
        let a2 = FingerprintVariation(seed: FingerprintSeed.value(for: "iG9CE55wbtY"))
        let b = FingerprintVariation(seed: FingerprintSeed.value(for: "KiE4Pk_gu50"))
        #expect(a1 == a2)
        #expect(a1 != b)
        for variation in [a1, b] {
            #expect((0.04...0.16).contains(variation.rhythmAmplitude))
            #expect((5...13).contains(variation.rhythmPeriod))
            #expect(abs(variation.gradientAngle) <= 0.17)
            #expect((0.44...0.56).contains(variation.barWidthRatio))
        }
    }

    // MARK: - Geometry

    @Test func marksFillTheRectInOrderAndStayMirrored() {
        let rect = CGRect(x: 20, y: 10, width: 480, height: 51)
        let marks = FingerprintGeometry.marks(for: Self.sample, in: rect)

        #expect(marks.count == 120)
        #expect(zip(marks, marks.dropFirst()).allSatisfy { $0.rect.midX < $1.rect.midX && $0.rect.maxX <= $1.rect.minX })
        #expect(marks.allSatisfy { rect.insetBy(dx: -0.01, dy: -0.01).contains($0.rect) })
        #expect(marks.allSatisfy { abs($0.rect.midY - rect.midY) < 0.001 }, "bars are centred on the axis")
        #expect((40..<60).allSatisfy { marks[$0].isDot })
        #expect(marks.filter(\.isDot).count == 20)

        let tallest = marks.max { $0.rect.height < $1.rect.height }
        #expect(abs((tallest?.rect.height ?? 0) - rect.height) < 0.001)

        let pitches = FingerprintGeometry.spacing(count: 120, totalWidth: 480, variation: Self.sample.variation)
        #expect(abs(pitches.reduce(0, +) - 480) < 0.0001)
        #expect(pitches.allSatisfy { abs($0 - 4) < 4 * 0.2 }, "spacing varies only subtly")
    }

    @Test func growthStartsFlatAndEndsAtFullShape() {
        let rect = CGRect(x: 0, y: 0, width: 480, height: 51)
        let start = FingerprintGeometry.marks(for: Self.sample, in: rect, growth: 0)
        let end = FingerprintGeometry.marks(for: Self.sample, in: rect, growth: 1)
        #expect(start.filter { !$0.isDot }.allSatisfy { $0.rect.height <= $0.rect.width + 0.001 })
        #expect(end == FingerprintGeometry.marks(for: Self.sample, in: rect))
    }

    // MARK: - Rendering

    @Test func rendersInkOnlyWhereMarksAre() throws {
        let style = FingerprintRenderer.Style(color: CGColor(srgbRed: 0.2, green: 0.3, blue: 0.8, alpha: 1))
        let image = try #require(FingerprintRenderer.image(Self.sample, size: CGSize(width: 480, height: 51), scale: 1, style: style))
        let pixels = try alphaChannel(of: image)

        // A silent slice has only a small dot on the axis: nothing near the top edge.
        let silentColumn = Int(FingerprintGeometry.marks(for: Self.sample, in: CGRect(x: 0, y: 0, width: 480, height: 51))[50].rect.midX)
        #expect(pixels[2 * image.width + silentColumn] == 0)
        // The busiest slice reaches the top.
        let burstColumn = Int(FingerprintGeometry.marks(for: Self.sample, in: CGRect(x: 0, y: 0, width: 480, height: 51))[105].rect.midX)
        #expect((0..<4).contains { pixels[$0 * image.width + burstColumn] > 0 })
    }

    /// Writes sample PNGs for visual review when `YTTOPDF_RENDER_DIR` is set.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["YTTOPDF_RENDER_DIR"] != nil))
    func writeSamples() throws {
        let directory = URL(filePath: ProcessInfo.processInfo.environment["YTTOPDF_RENDER_DIR"] ?? "/tmp")
        let accent = CGColor(srgbRed: 0.16, green: 0.33, blue: 0.85, alpha: 1)
        let paper = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)

        let band = FingerprintRenderer.Style(color: accent)
        try Self.writePNG(FingerprintRenderer.image(Self.sample, size: CGSize(width: 480, height: 51), scale: 3, style: band, background: paper), to: directory, name: "synthetic-band")

        var header = FingerprintRenderer.Style(color: accent)
        header.highlight = 62...80
        try Self.writePNG(FingerprintRenderer.image(Self.sample, size: CGSize(width: 150, height: 11), scale: 6, style: header, background: paper), to: directory, name: "synthetic-header")

        let other = SpeechFingerprint(wordStarts: Self.sampleStarts, duration: 120, seed: FingerprintSeed.value(for: "zyxwvutsrqp"))
        try Self.writePNG(FingerprintRenderer.image(other, size: CGSize(width: 480, height: 51), scale: 3, style: band, background: paper), to: directory, name: "synthetic-band-other-seed")

        var growing = band
        growing.growth = 0.5
        try Self.writePNG(FingerprintRenderer.image(Self.sample, size: CGSize(width: 480, height: 51), scale: 3, style: growing, background: paper), to: directory, name: "synthetic-band-growing")
    }

    // MARK: - Helpers

    static func writePNG(_ image: CGImage?, to directory: URL, name: String) throws {
        let image = try #require(image)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "\(name).png")
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
    }

    private func alphaChannel(of image: CGImage) throws -> [UInt8] {
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let context = try #require(CGContext(
            data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return stride(from: 3, to: pixels.count, by: 4).map { pixels[$0] }
    }
}
