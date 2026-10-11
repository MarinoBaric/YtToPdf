import AppKit
import SwiftUI

/// The finished transcript on a clean reading surface, with search and copy.
struct TranscriptPreview: View {
    let transcript: Transcript
    let metadata: VideoMetadata
    let options: TranscriptOptions
    let isExportingPDF: Bool
    let export: (ExportFormat) -> Void
    /// Scrolls the enclosing scroll view to a block.
    let scrollTo: (TranscriptBlock.ID) -> Void

    @State private var query = ""
    @State private var currentMatch = 0
    @State private var didCopy = false

    private var blocks: [TranscriptBlock] {
        TranscriptLayout.blocks(for: transcript, mode: options.timestampMode)
    }

    var body: some View {
        let blocks = blocks
        let matches = SearchMatches(query: query, blocks: blocks)

        VStack(alignment: .leading, spacing: 16) {
            header(matches: matches)

            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(blocks) { block in
                    TranscriptBlockRow(
                        block: block,
                        options: options,
                        link: YouTubeLink(videoID: metadata.id),
                        highlights: matches.ranges(in: block.id),
                        currentHighlight: matches.isCurrent(blockID: block.id, index: currentMatch)
                    )
                    .padding(.top, block.id == 0 ? 0 : (block.startsParagraph ? 18 : 6))
                    .id(block.id)
                }
            }
            .surface(padding: 32)
        }
        .onChange(of: query) {
            currentMatch = 0
            if let first = matches.blockID(at: 0) { scrollTo(first) }
        }
    }

    // MARK: - Header

    private func header(matches: SearchMatches) -> some View {
        // One row when there's room; otherwise the controls move under the title.
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 16) {
                title
                Spacer(minLength: 12)
                controls(matches: matches)
            }
            VStack(alignment: .leading, spacing: 12) {
                title
                controls(matches: matches)
            }
        }
        .animation(.smooth(duration: 0.2), value: query.isEmpty)
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Transcript")
                .font(.title2.weight(.semibold))
            Text("\(transcript.wordCount.formatted()) words · \(transcript.source.label)")
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .fixedSize()
    }

    private func controls(matches: SearchMatches) -> some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                searchField(matches: matches)
                if !query.isEmpty {
                    Button("Previous Match", systemImage: "chevron.up") { step(-1, in: matches) }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.glass)
                        .disabled(matches.count == 0)
                    Button("Next Match", systemImage: "chevron.down") { step(1, in: matches) }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.glass)
                        .disabled(matches.count == 0)
                }
                Button(action: copyAll) {
                    Label(didCopy ? "Copied" : "Copy All", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.glass)
                ExportMenu(isExportingPDF: isExportingPDF, export: export)
            }
            .fixedSize()
        }
    }

    private func searchField(matches: SearchMatches) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search transcript", text: $query)
                .textFieldStyle(.plain)
                .frame(width: 150)
                .onSubmit { step(1, in: matches) }
            if !query.isEmpty {
                Text(matches.count == 0 ? "None" : "\(min(currentMatch + 1, matches.count)) of \(matches.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    // MARK: - Actions

    private func step(_ direction: Int, in matches: SearchMatches) {
        guard matches.count > 0 else { return }
        currentMatch = (currentMatch + direction + matches.count) % matches.count
        if let id = matches.blockID(at: currentMatch) { scrollTo(id) }
    }

    private func copyAll() {
        let text = PlainTextRenderer.render(transcript, metadata: metadata, options: options)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        withAnimation(.smooth) { didCopy = true }
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            withAnimation(.smooth) { didCopy = false }
        }
    }
}

/// Every search match across the transcript, in reading order.
private struct SearchMatches {
    private let byBlock: [TranscriptBlock.ID: [Range<String.Index>]]
    /// (block, index of the match within that block), flattened in reading order.
    private let ordered: [(block: TranscriptBlock.ID, local: Int)]

    init(query: String, blocks: [TranscriptBlock]) {
        var byBlock: [TranscriptBlock.ID: [Range<String.Index>]] = [:]
        var ordered: [(TranscriptBlock.ID, Int)] = []
        for block in blocks {
            let ranges = TextSearch.ranges(of: query, in: block.text)
            guard !ranges.isEmpty else { continue }
            byBlock[block.id] = ranges
            ordered += ranges.indices.map { (block.id, $0) }
        }
        self.byBlock = byBlock
        self.ordered = ordered
    }

    var count: Int { ordered.count }

    func ranges(in blockID: TranscriptBlock.ID) -> [Range<String.Index>] { byBlock[blockID] ?? [] }

    func blockID(at index: Int) -> TranscriptBlock.ID? {
        ordered.indices.contains(index) ? ordered[index].block : nil
    }

    /// The index, within `blockID`, of the current match if it's in that block.
    func isCurrent(blockID: TranscriptBlock.ID, index: Int) -> Int? {
        guard ordered.indices.contains(index), ordered[index].block == blockID else { return nil }
        return ordered[index].local
    }
}
