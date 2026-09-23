import CoreText
import Foundation

/// The Inter faces bundled with the app (SIL Open Font License, see `Inter-OFL.txt`).
/// Used for PDF output, where the font is embedded; the app UI uses the system font.
nonisolated enum InterFont: String, CaseIterable, Sendable {
    case regular = "Inter-Regular"
    case italic = "Inter-Italic"
    case medium = "Inter-Medium"
    case semiBold = "Inter-SemiBold"
    case bold = "Inter-Bold"
    case displaySemiBold = "InterDisplay-SemiBold"
    case displayBold = "InterDisplay-Bold"

    var postScriptName: String { rawValue }

    /// The face at `size`, loaded straight from the bundled file so a missing registration can
    /// never silently swap in Helvetica.
    func font(size: CGFloat, tabularNumbers: Bool = false) -> CTFont {
        let base = Self.descriptors[self] ?? CTFontDescriptorCreateWithNameAndSize(postScriptName as CFString, size)
        guard tabularNumbers else { return CTFontCreateWithFontDescriptor(base, size, nil) }

        let tabular: [CFString: Any] = [
            kCTFontFeatureSettingsAttribute: [[kCTFontOpenTypeFeatureTag: "tnum", kCTFontOpenTypeFeatureValue: 1]],
        ]
        let descriptor = CTFontDescriptorCreateCopyWithAttributes(base, tabular as CFDictionary)
        return CTFontCreateWithFontDescriptor(descriptor, size, nil)
    }

    /// Built once, never mutated. `CTFontDescriptor` is immutable and thread-safe, but Core Text
    /// doesn't mark it `Sendable`, hence `nonisolated(unsafe)`.
    nonisolated(unsafe) private static let descriptors: [InterFont: CTFontDescriptor] = {
        var result: [InterFont: CTFontDescriptor] = [:]
        for face in InterFont.allCases {
            guard let url = Bundle.main.url(forResource: face.rawValue, withExtension: "ttf"),
                  let list = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
                  let descriptor = list.first
            else { continue }
            result[face] = descriptor
        }
        return result
    }()
}

nonisolated enum FontRegistrar {
    /// Registers every bundled `.ttf` for this process. Returns the files that failed,
    /// ignoring ones that were already registered.
    @discardableResult
    static func registerBundledFonts(in bundle: Bundle = .main) -> [URL] {
        let urls = bundle.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? []
        return urls.filter { !register($0) }
    }

    private static func register(_ url: URL) -> Bool {
        var error: Unmanaged<CFError>?
        if CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) { return true }
        guard let cfError = error?.takeRetainedValue() else { return false }
        return CFErrorGetCode(cfError) == CTFontManagerError.alreadyRegistered.rawValue
    }
}
