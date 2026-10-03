import SwiftUI

/// The Speech Fingerprint as a SwiftUI view, drawn by the same renderer the PDF uses.
struct SpeechFingerprintView: View {
    let fingerprint: SpeechFingerprint
    var color: Color = .accentColor
    /// Highlights the bars in this range and fades the rest.
    var highlight: ClosedRange<TimeInterval>?
    var showsTimeLabels = true
    /// Grows the bars in from the axis the first time the view appears.
    var animatesIn = true

    @Environment(\.self) private var environment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var growth = 0.0

    var body: some View {
        VStack(spacing: 6) {
            FingerprintCanvas(
                fingerprint: fingerprint,
                color: color.resolve(in: environment).cgColor,
                highlight: highlight,
                growth: growth
            )
            if showsTimeLabels {
                HStack {
                    Text(TimeFormatting.duration(0))
                    Spacer()
                    Text(TimeFormatting.duration(fingerprint.duration / 2))
                    Spacer()
                    Text(TimeFormatting.duration(fingerprint.duration))
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
            }
        }
        .onAppear {
            guard growth < 1 else { return }
            if animatesIn && !reduceMotion {
                withAnimation(.smooth(duration: 1.1)) { growth = 1 }
            } else {
                growth = 1
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Speech fingerprint")
        .accessibilityValue(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        let silent = fingerprint.wordCounts.count { $0 == 0 }
        let share = Double(silent) / Double(max(fingerprint.sliceCount, 1))
        return "Speech across \(TimeFormatting.duration(fingerprint.duration)), silent about \(Int((share * 100).rounded())) percent of the time."
    }
}

/// Redraws on every animation frame of `growth`.
private struct FingerprintCanvas: View, Animatable {
    let fingerprint: SpeechFingerprint
    let color: CGColor
    let highlight: ClosedRange<TimeInterval>?
    var growth: Double

    var animatableData: Double {
        get { growth }
        set { growth = newValue }
    }

    var body: some View {
        Canvas { context, size in
            context.withCGContext { cgContext in
                var style = FingerprintRenderer.Style(color: color)
                style.highlight = highlight
                style.growth = growth
                FingerprintRenderer.draw(fingerprint, in: cgContext, rect: CGRect(origin: .zero, size: size), style: style)
            }
        }
    }
}

#Preview {
    let starts = (0..<900).map { index in
        // Uneven speech with a few silent gaps, for previewing the shape.
        let base = Double(index) * 0.33
        return base + (index % 97 < 6 ? 25 : 0)
    }
    SpeechFingerprintView(fingerprint: SpeechFingerprint(wordStarts: starts, duration: 330, seed: FingerprintSeed.value(for: "preview")))
        .frame(width: 560, height: 70)
        .padding()
}
