import CoreGraphics
import Foundation
import ImageIO
import Observation
import UniformTypeIdentifiers

/// App-wide preferences, edited in Settings and read when exporting.
@Observable
final class AppSettings {
    enum AccentMode: String, CaseIterable, Identifiable {
        case automatic
        case custom

        var id: String { rawValue }
        var label: String { self == .automatic ? "From thumbnail" : "Custom" }
    }

    /// Curated accents that print well; all pass WCAG AA contrast on white.
    static let presetAccents: [CGColor] = [
        PDFTheme.defaultAccent,
        CGColor(srgbRed: 0.05, green: 0.45, blue: 0.40, alpha: 1),
        CGColor(srgbRed: 0.60, green: 0.20, blue: 0.48, alpha: 1),
        CGColor(srgbRed: 0.75, green: 0.25, blue: 0.13, alpha: 1),
        CGColor(srgbRed: 0.34, green: 0.27, blue: 0.70, alpha: 1),
        CGColor(srgbRed: 0.20, green: 0.24, blue: 0.30, alpha: 1),
    ]

    var accentMode: AccentMode {
        didSet { defaults.set(accentMode.rawValue, forKey: Keys.accentMode) }
    }

    var customAccent: CGColor {
        didSet { defaults.set(Self.components(of: customAccent), forKey: Keys.customAccent) }
    }

    var defaultOptions: TranscriptOptions {
        didSet { DefaultOptions.save(defaultOptions, to: defaults) }
    }

    /// The uploaded logo, or `nil` for YtToPdf's own mark.
    private(set) var logo: CGImage?

    private let defaults: UserDefaults
    let logoURL: URL

    init(defaults: UserDefaults = .standard, logoURL: URL = AppSettings.defaultLogoURL) {
        self.defaults = defaults
        self.logoURL = logoURL
        accentMode = defaults.string(forKey: Keys.accentMode).flatMap(AccentMode.init(rawValue:)) ?? .automatic
        customAccent = (defaults.array(forKey: Keys.customAccent) as? [Double]).flatMap(Self.color(from:)) ?? PDFTheme.defaultAccent
        defaultOptions = DefaultOptions.load(from: defaults)
        logo = Self.loadImage(at: logoURL)
    }

    static var defaultLogoURL: URL {
        URL.applicationSupportDirectory
            .appending(path: "YtToPdf", directoryHint: .isDirectory)
            .appending(path: "Logo.png", directoryHint: .notDirectory)
    }

    // MARK: - Accent

    /// The PDF accent for a video: from its thumbnail in automatic mode (falling back to the
    /// default if the thumbnail has no usable colour), otherwise the custom colour.
    func accent(forThumbnail thumbnail: Data?) -> CGColor {
        switch accentMode {
        case .custom: customAccent
        case .automatic: thumbnail.flatMap(ThumbnailPalette.accent(from:)) ?? PDFTheme.defaultAccent
        }
    }

    // MARK: - Logo

    enum LogoError: Error, LocalizedError {
        case unreadable
        case couldNotSave

        var errorDescription: String? {
            switch self {
            case .unreadable: "That file isn't an image YtToPdf can read."
            case .couldNotSave: "The logo couldn't be saved."
            }
        }
    }

    /// Copies an image into the app's folder as a PNG no taller than 600 px, so the original
    /// can move or change without affecting PDFs.
    func setLogo(from url: URL) throws(LogoError) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 1200,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { throw .unreadable }

        do {
            try FileManager.default.createDirectory(at: logoURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            throw .couldNotSave
        }
        guard let destination = CGImageDestinationCreateWithURL(logoURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw .couldNotSave
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw .couldNotSave }
        logo = image
    }

    func removeLogo() {
        try? FileManager.default.removeItem(at: logoURL)
        logo = nil
    }

    // MARK: - Persistence helpers

    private enum Keys {
        static let accentMode = "pdfAccentMode"
        static let customAccent = "pdfCustomAccent"
    }

    private static func components(of color: CGColor) -> [Double] {
        let srgb = CGColorSpace(name: CGColorSpace.sRGB).flatMap { color.converted(to: $0, intent: .defaultIntent, options: nil) } ?? color
        return (srgb.components ?? [0, 0, 0, 1]).prefix(3).map(Double.init)
    }

    private static func color(from components: [Double]) -> CGColor? {
        guard components.count == 3 else { return nil }
        return CGColor(srgbRed: components[0], green: components[1], blue: components[2], alpha: 1)
    }

    private static func loadImage(at url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
