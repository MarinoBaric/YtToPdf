import SwiftUI

/// The pipeline's steps with the current one highlighted and, when measurable, its progress.
struct ProgressStepsView: View {
    let steps: [TranscriptPipeline.Step]
    let progress: TranscriptPipeline.Progress
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(steps, id: \.self) { step in
                StepRow(
                    title: step.title,
                    state: state(of: step),
                    fraction: step == progress.step ? progress.fraction : nil
                )
            }
            CancelRow(cancel: cancel)
        }
        .surface()
    }

    private func state(of step: TranscriptPipeline.Step) -> StepRow.State {
        if step == progress.step { return .current }
        return step < progress.step ? .done : .pending
    }
}

/// A single long-running task, e.g. a model download.
struct SingleTaskProgressView: View {
    let title: String
    let fraction: Double
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            StepRow(title: title, state: .current, fraction: fraction)
            CancelRow(cancel: cancel)
        }
        .surface()
    }
}

struct StepRow: View {
    enum State { case done, current, pending }

    let title: String
    let state: State
    let fraction: Double?

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            icon.frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(title)
                        .font(.body.weight(state == .current ? .semibold : .regular))
                        .foregroundStyle(state == .pending ? .tertiary : .primary)
                    Spacer()
                    if state == .current, let fraction {
                        Text(fraction, format: .percent.precision(.fractionLength(0)))
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .contentTransition(.numericText())
                    }
                }
                if state == .current, let fraction {
                    ProgressView(value: fraction)
                        .progressViewStyle(.linear)
                        .animation(.smooth, value: fraction)
                }
            }
        }
        .animation(.smooth, value: state)
    }

    @ViewBuilder
    private var icon: some View {
        switch state {
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(.tint)
                .transition(.scale.combined(with: .opacity))
        case .current:
            ProgressView().controlSize(.small)
        case .pending:
            Image(systemName: "circle")
                .font(.title3)
                .foregroundStyle(.quaternary)
        }
    }
}

private struct CancelRow: View {
    let cancel: () -> Void

    var body: some View {
        HStack {
            Spacer()
            Button("Cancel", role: .cancel, action: cancel)
                .buttonStyle(.glass)
                .keyboardShortcut(.cancelAction)
        }
    }
}
