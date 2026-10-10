import AppKit
import SwiftUI

/// A calm, opaque surface for content (cards, the transcript). Glass is reserved for controls.
struct Surface: ViewModifier {
    var cornerRadius: CGFloat = 20
    var padding: CGFloat = 20

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Color(nsColor: .textBackgroundColor), in: .rect(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(.separator.opacity(0.5), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.04), radius: 10, y: 3)
    }
}

extension View {
    func surface(cornerRadius: CGFloat = 20, padding: CGFloat = 20) -> some View {
        modifier(Surface(cornerRadius: cornerRadius, padding: padding))
    }
}

/// Small uppercase section label used above cards.
struct SectionLabel: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.caption.weight(.semibold))
            .tracking(0.8)
            .foregroundStyle(.secondary)
    }
}
