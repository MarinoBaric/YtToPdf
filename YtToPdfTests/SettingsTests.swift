import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import YtToPdf

@MainActor
@Suite("Settings and accent colour")
struct SettingsTests {
    private let defaults: UserDefaults
    private let folder: URL

    init() throws {
        defaults = try #require(UserDefaults(suiteName: "SettingsTests-\(UUID().uuidString)"))
        folder = FileManager.default.temporaryDirectory.appending(path: "SettingsTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    private func components(_ color: CGColor) -> (r: Double, g: Double, b: Double) {
        let values = color.components ?? [0, 0, 0]
        return (values[0], values[1], values[2])
    }

    private func pngData(width: Int, height: Int, pixel: (Int, Int) -> (UInt8, UInt8, UInt8)) throws -> Data {
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let (r, g, b) = pixel(x, y)
                let index = (y * width + x) * 4
                bytes[index] = r; bytes[index + 1] = g; bytes[index + 2] = b
            }
        }
        let context = try #require(CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                             space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data as CFMutableData, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    // MARK: - Thumbnail accent

    @Test func picksTheThumbnailsColourAndKeepsItReadable() throws {
        // A mostly grey frame with an orange-red object in it.
        let data = try pngData(width: 96, height: 54) { x, y in
            (30..<60).contains(x) && (10..<40).contains(y) ? (230, 80, 40) : (128, 128, 130)
        }
        let accent = try #require(ThumbnailPalette.accent(from: data))
        let rgb = components(accent)
        #expect(rgb.r > rgb.g && rgb.r > rgb.b, "stays red-orange")
        #expect(ThumbnailPalette.contrastOnWhite(rgb) >= ThumbnailPalette.minimumContrastOnWhite)
    }

    @Test func blackAndWhiteThumbnailsFallBack() throws {
        let data = try pngData(width: 64, height: 36) { x, _ in
            let value = UInt8(x * 4); return (value, value, value)
        }
        #expect(ThumbnailPalette.accent(from: data) == nil)
        #expect(ThumbnailPalette.accent(from: Data("not an image".utf8)) == nil)
    }

    @Test func presetAccentsAreAllReadableOnWhite() {
        for preset in AppSettings.presetAccents {
            #expect(ThumbnailPalette.contrastOnWhite(components(preset)) >= ThumbnailPalette.minimumContrastOnWhite)
        }
    }

    // MARK: - Persistence

    @Test func accentAndDefaultsPersist() {
        let first = AppSettings(defaults: defaults, logoURL: folder.appending(path: "Logo.png"))
        #expect(first.accentMode == .automatic)
        first.accentMode = .custom
        first.customAccent = AppSettings.presetAccents[2]
        first.defaultOptions.timestampMode = .every60

        let second = AppSettings(defaults: defaults, logoURL: folder.appending(path: "Logo.png"))
        #expect(second.accentMode == .custom)
        #expect(second.customAccent == AppSettings.presetAccents[2])
        #expect(second.defaultOptions.timestampMode == .every60)
        #expect(DefaultOptions.load(from: defaults).timestampMode == .every60, "new transcripts pick up the default")
        #expect(second.accent(forThumbnail: nil) == AppSettings.presetAccents[2])
    }

    @Test func automaticAccentFallsBackWithoutAThumbnail() {
        let settings = AppSettings(defaults: defaults, logoURL: folder.appending(path: "Logo.png"))
        #expect(settings.accent(forThumbnail: nil) == PDFTheme.defaultAccent)
    }

    @Test func logoIsCopiedAsPNGAndRemovable() throws {
        let source = folder.appending(path: "brand.png")
        try pngData(width: 400, height: 120) { _, _ in (20, 40, 200) }.write(to: source)
        let logoURL = folder.appending(path: "Stored/Logo.png")

        let settings = AppSettings(defaults: defaults, logoURL: logoURL)
        try settings.setLogo(from: source)
        #expect(settings.logo?.width == 400)
        #expect(FileManager.default.fileExists(atPath: logoURL.path))
        #expect(AppSettings(defaults: defaults, logoURL: logoURL).logo != nil, "reloaded on next launch")

        settings.removeLogo()
        #expect(settings.logo == nil)
        #expect(!FileManager.default.fileExists(atPath: logoURL.path))
        #expect(throws: AppSettings.LogoError.unreadable) { try settings.setLogo(from: folder.appending(path: "missing.png")) }
    }

    @Test func customLogoAndAccentReachThePDF() throws {
        let source = folder.appending(path: "brand.png")
        try pngData(width: 300, height: 100) { _, _ in (200, 30, 30) }.write(to: source)
        let settings = AppSettings(defaults: defaults, logoURL: folder.appending(path: "Logo.png"))
        try settings.setLogo(from: source)

        var input = PDFExporterTests.input()
        input.theme = PDFTheme(accent: AppSettings.presetAccents[1])
        input.logo = settings.logo
        let data = try PDFExporter.render(input)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("/Subtype /Image"), "the logo is embedded as an image")
    }
}
