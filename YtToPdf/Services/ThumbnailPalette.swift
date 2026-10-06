import CoreGraphics
import Foundation
import ImageIO

/// Picks a tasteful accent colour from a video thumbnail for the PDF.
///
/// The most prominent *chromatic* hue wins (greys, near-black and near-white are ignored), then
/// it's tuned for print: saturation and brightness are pulled into a calm range, and the colour
/// is darkened until text in it reads clearly on white paper.
nonisolated enum ThumbnailPalette {
    /// WCAG AA for normal text, so timestamps and links in the accent stay readable.
    static let minimumContrastOnWhite = 4.5

    /// The accent for this thumbnail, or `nil` when it has no meaningful colour (e.g. black and white).
    static func accent(from imageData: Data) -> CGColor? {
        guard let pixels = sample(imageData) else { return nil }
        return accent(fromRGB: pixels)
    }

    /// `pixels` holds RGB triples in 0...1.
    static func accent(fromRGB pixels: [(r: Double, g: Double, b: Double)]) -> CGColor? {
        let bucketCount = 36
        var weights = [Double](repeating: 0, count: bucketCount)
        var hueX = [Double](repeating: 0, count: bucketCount)
        var hueY = [Double](repeating: 0, count: bucketCount)
        var saturationSum = [Double](repeating: 0, count: bucketCount)
        var brightnessSum = [Double](repeating: 0, count: bucketCount)

        for pixel in pixels {
            let (hue, saturation, brightness) = hsb(pixel.r, pixel.g, pixel.b)
            guard saturation >= 0.2, brightness >= 0.18, brightness <= 0.98 else { continue }
            // Favour vivid, mid-bright pixels: they carry a thumbnail's character.
            let weight = saturation * (1 - abs(brightness - 0.6))
            let bucket = min(bucketCount - 1, Int(hue * Double(bucketCount)))
            weights[bucket] += weight
            hueX[bucket] += cos(hue * 2 * .pi) * weight
            hueY[bucket] += sin(hue * 2 * .pi) * weight
            saturationSum[bucket] += saturation * weight
            brightnessSum[bucket] += brightness * weight
        }

        // Neighbouring buckets belong to the same colour; score each with its neighbours.
        let scores = weights.indices.map { index in
            weights[index] + 0.5 * (weights[(index + 1) % bucketCount] + weights[(index + bucketCount - 1) % bucketCount])
        }
        guard let best = scores.indices.max(by: { scores[$0] < scores[$1] }),
              weights[best] > 0,
              weights.reduce(0, +) >= Double(pixels.count) * 0.03
        else { return nil }

        var hue = atan2(hueY[best], hueX[best]) / (2 * .pi)
        if hue < 0 { hue += 1 }
        let saturation = min(0.78, max(0.45, saturationSum[best] / weights[best]))
        var brightness = min(0.62, max(0.4, brightnessSum[best] / weights[best]))

        var color = rgb(hue: hue, saturation: saturation, brightness: brightness)
        while contrastOnWhite(color) < minimumContrastOnWhite, brightness > 0.2 {
            brightness -= 0.03
            color = rgb(hue: hue, saturation: saturation, brightness: brightness)
        }
        return CGColor(srgbRed: color.r, green: color.g, blue: color.b, alpha: 1)
    }

    // MARK: - Colour maths

    static func contrastOnWhite(_ color: (r: Double, g: Double, b: Double)) -> Double {
        1.05 / (relativeLuminance(color) + 0.05)
    }

    static func relativeLuminance(_ color: (r: Double, g: Double, b: Double)) -> Double {
        func linear(_ channel: Double) -> Double {
            channel <= 0.040_45 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(color.r) + 0.7152 * linear(color.g) + 0.0722 * linear(color.b)
    }

    private static func hsb(_ r: Double, _ g: Double, _ b: Double) -> (Double, Double, Double) {
        let maximum = max(r, g, b), minimum = min(r, g, b), delta = maximum - minimum
        guard delta > 0 else { return (0, 0, maximum) }
        var hue: Double
        if maximum == r { hue = (g - b) / delta }
        else if maximum == g { hue = (b - r) / delta + 2 }
        else { hue = (r - g) / delta + 4 }
        hue /= 6
        if hue < 0 { hue += 1 }
        return (hue, delta / maximum, maximum)
    }

    private static func rgb(hue: Double, saturation: Double, brightness: Double) -> (r: Double, g: Double, b: Double) {
        let sector = hue * 6
        let fraction = sector - floor(sector)
        let p = brightness * (1 - saturation)
        let q = brightness * (1 - saturation * fraction)
        let t = brightness * (1 - saturation * (1 - fraction))
        switch Int(sector) % 6 {
        case 0: return (brightness, t, p)
        case 1: return (q, brightness, p)
        case 2: return (p, brightness, t)
        case 3: return (p, q, brightness)
        case 4: return (t, p, brightness)
        default: return (brightness, p, q)
        }
    }

    /// Decodes a small version of the image and returns its pixels as RGB in 0...1.
    private static func sample(_ data: Data) -> [(r: Double, g: Double, b: Double)]? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 64,
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }

        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        return stride(from: 0, to: bytes.count, by: 4).map {
            (Double(bytes[$0]) / 255, Double(bytes[$0 + 1]) / 255, Double(bytes[$0 + 2]) / 255)
        }
    }
}
