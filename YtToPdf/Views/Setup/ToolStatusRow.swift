import SwiftUI

struct ToolStatusRow: View {
    let tool: ExternalTool
    let location: URL?

    private var isInstalled: Bool { location != nil }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: isInstalled ? "checkmark.circle.fill" : "circle.dashed")
                .font(.title2)
                .foregroundStyle(isInstalled ? AnyShapeStyle(.green) : AnyShapeStyle(.tertiary))
                .frame(width: 26)
                .contentTransition(.symbolEffect(.replace))

            VStack(alignment: .leading, spacing: 2) {
                Text(tool.displayName)
                    .font(.headline)
                Text(location?.path(percentEncoded: false) ?? tool.purpose)
                    .font(isInstalled ? .caption.monospaced() : .callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 12)

            Text(isInstalled ? "Installed" : "Missing")
                .font(.callout.weight(.medium))
                .foregroundStyle(isInstalled ? .secondary : .primary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }
}
