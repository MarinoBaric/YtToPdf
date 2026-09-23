import CoreText
import Testing
@testable import YtToPdf

@Suite("Bundled Inter fonts")
struct FontRegistrarTests {
    @Test func allBundledFontsRegister() {
        #expect(FontRegistrar.registerBundledFonts().isEmpty)
    }

    @Test(arguments: InterFont.allCases)
    func faceResolvesToInterNotAFallback(_ face: InterFont) {
        FontRegistrar.registerBundledFonts()
        let font = face.font(size: 12)
        #expect(CTFontCopyPostScriptName(font) as String == face.postScriptName)
    }
}
