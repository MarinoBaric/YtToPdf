import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Accent colour and logo for exported PDFs, with a live preview.
struct PDFSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @State private var isChoosingLogo = false
    @State private var logoError: String?

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                PDFHeadingPreview(accent: previewAccent, logo: settings.logo)
                    .listRowInsets(EdgeInsets())
            }

            Section("Accent colour") {
                Picker("Accent", selection: $settings.accentMode) {
                    ForEach(AppSettings.AccentMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)

                if settings.accentMode == .automatic {
                    Text("Each PDF takes a calm, readable colour from its video's thumbnail. Black-and-white thumbnails use the default blue.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 10) {
                        ForEach(Array(AppSettings.presetAccents.enumerated()), id: \.offset) { _, color in
                            AccentSwatch(color: color, isSelected: settings.customAccent == color) {
                                settings.customAccent = color
                            }
                        }
                        Spacer()
                        ColorPicker("Other colour", selection: $settings.customAccent, supportsOpacity: false)
                            .labelsHidden()
                    }
                }
            }

            Section {
                HStack(spacing: 14) {
                    LogoThumbnail(logo: settings.logo)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(settings.logo == nil ? "YtToPdf mark" : "Your logo")
                        Text("Shown at the top of the first page and, smaller, on every page after.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    GlassEffectContainer(spacing: 8) {
                        HStack(spacing: 8) {
                            if settings.logo != nil {
                                Button("Remove", role: .destructive, action: settings.removeLogo)
                                    .buttonStyle(.glass)
                            }
                            Button("Choose…") { isChoosingLogo = true }
                                .buttonStyle(.glass)
                        }
                    }
                }
            } header: {
                Text("Logo")
            } footer: {
                Text("PNG, JPEG, HEIC or TIFF. A wide logo with a transparent background looks best.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .fileImporter(isPresented: $isChoosingLogo, allowedContentTypes: [.png, .jpeg, .heic, .tiff]) { result in
            switch result {
            case .success(let url):
                do throws(AppSettings.LogoError) {
                    try settings.setLogo(from: url)
                } catch {
                    logoError = error.localizedDescription
                }
            case .failure(let error):
                logoError = error.localizedDescription
            }
        }
        .alert("The logo couldn't be used", isPresented: .constant(logoError != nil)) {
            Button("OK") { logoError = nil }
        } message: {
            Text(logoError ?? "")
        }
    }

    private var previewAccent: CGColor {
        settings.accentMode == .custom ? settings.customAccent : PDFTheme.defaultAccent
    }
}

private struct AccentSwatch: View {
    let color: CGColor
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            Circle()
                .fill(Color(cgColor: color))
                .frame(width: 22, height: 22)
                .overlay {
                    Circle().strokeBorder(.white.opacity(0.9), lineWidth: isSelected ? 2 : 0)
                }
                .overlay {
                    Circle().strokeBorder(Color(cgColor: color), lineWidth: isSelected ? 1 : 0).padding(-3)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Accent colour")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct LogoThumbnail: View {
    let logo: CGImage?

    var body: some View {
        Group {
            if let logo {
                Image(decorative: logo, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                DefaultMark(accent: PDFTheme.defaultAccent)
            }
        }
        .frame(width: 64, height: 32)
    }
}

/// A miniature of the PDF's first page heading: logo, label and fingerprint in the accent.
private struct PDFHeadingPreview: View {
    let accent: CGColor
    let logo: CGImage?

    private static let sample = SpeechFingerprint(
        wordStarts: (0..<700).map { Double($0) * 0.42 + ($0 % 83 < 5 ? 14 : 0) },
        duration: 310,
        seed: FingerprintSeed.value(for: "settings-preview")
    )

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Group {
                if let logo {
                    Image(decorative: logo, scale: 1).resizable().aspectRatio(contentMode: .fit)
                } else {
                    HStack(spacing: 6) {
                        DefaultMark(accent: accent).frame(width: 18, height: 18)
                        Text("YtToPdf").font(.system(size: 10, weight: .semibold))
                    }
                }
            }
            .frame(height: 18, alignment: .leading)

            Text("TRANSCRIPT")
                .font(.system(size: 7, weight: .semibold))
                .tracking(1.8)
                .foregroundStyle(Color(cgColor: accent))
            Text("Your video's title, set large")
                .font(.system(size: 17, weight: .bold))
            SpeechFingerprintView(fingerprint: Self.sample, color: Color(cgColor: accent), showsTimeLabels: false, animatesIn: false)
                .frame(height: 26)
        }
        .foregroundStyle(.black)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        // The page is always white paper, in light and dark mode alike.
        .background(.white, in: .rect(cornerRadius: 8))
        .padding(12)
    }
}

/// YtToPdf's default mark, as drawn in the PDF.
struct DefaultMark: View {
    let accent: CGColor

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let bars: [CGFloat] = [0.32, 0.62, 0.9, 0.5, 0.74]
            let inset = side * 0.2
            let pitch = (side - 2 * inset) / CGFloat(bars.count)
            ZStack {
                RoundedRectangle(cornerRadius: side * 0.26).fill(Color(cgColor: accent))
                HStack(spacing: pitch * 0.48) {
                    ForEach(bars.indices, id: \.self) { index in
                        Capsule()
                            .fill(.white)
                            .frame(width: pitch * 0.52, height: (side - 2 * inset) * bars[index])
                    }
                }
            }
            .frame(width: side, height: side)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
