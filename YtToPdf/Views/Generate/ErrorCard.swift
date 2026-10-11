import SwiftUI

/// Explains a failure in plain language, with a fix command when there is one.
struct ErrorCard: View {
    let error: PipelineError
    let retry: () -> Void
    let dismiss: () -> Void

    private var symbol: String {
        switch error {
        case .youTube(.noNetwork): "wifi.exclamationmark"
        case .youTube(.privateVideo), .youTube(.ageRestricted), .youTube(.membersOnly): "lock.fill"
        case .youTube(.invalidURL): "link.badge.plus"
        case .youTube(.ytDlpOutdated), .tools: "wrench.and.screwdriver.fill"
        default: "exclamationmark.triangle.fill"
        }
    }

    /// Retrying can't help when the video itself is off-limits or the link is wrong.
    private var canRetry: Bool {
        switch error {
        case .youTube(.invalidURL), .youTube(.privateVideo), .youTube(.ageRestricted),
             .youTube(.membersOnly), .youTube(.unavailable):
            false
        default:
            true
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.orange)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 8) {
                Text(error.errorDescription ?? "Something went wrong.")
                    .font(.headline)
                if let suggestion = error.recoverySuggestion {
                    Text(suggestion)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                if let command = error.fixCommand {
                    CommandBox(title: "Fix", command: command)
                        .padding(.top, 4)
                }

                GlassEffectContainer(spacing: 10) {
                    HStack(spacing: 10) {
                        if canRetry {
                            Button("Try Again", systemImage: "arrow.clockwise", action: retry)
                                .buttonStyle(.glassProminent)
                        }
                        Button("Dismiss", action: dismiss)
                            .buttonStyle(.glass)
                    }
                }
                .padding(.top, 6)
            }
            Spacer(minLength: 0)
        }
        .surface()
    }
}
