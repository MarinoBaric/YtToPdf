import AppKit
import SwiftData
import SwiftUI

/// Past transcripts, newest first, grouped by when they were made.
struct HistorySidebar: View {
    @Binding var selection: PersistentIdentifier?
    let delete: (TranscriptRecord) -> Void

    @Environment(\.historyIsPersistent) private var historyIsPersistent
    @State private var searchText = ""

    var body: some View {
        HistoryList(searchText: searchText, selection: $selection, delete: delete)
            .searchable(text: $searchText, placement: .sidebar, prompt: "Search transcripts")
            .navigationTitle("History")
            .safeAreaInset(edge: .bottom) {
                if !historyIsPersistent {
                    Label("History couldn't be opened, so transcripts won't be kept after you quit.", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(12)
                }
            }
    }
}

/// The filtered list. A separate view so the `@Query` can be rebuilt for each search.
private struct HistoryList: View {
    @Binding var selection: PersistentIdentifier?
    let delete: (TranscriptRecord) -> Void
    private let searchText: String

    @Query private var records: [TranscriptRecord]

    init(searchText: String, selection: Binding<PersistentIdentifier?>, delete: @escaping (TranscriptRecord) -> Void) {
        self.searchText = searchText.trimmingCharacters(in: .whitespaces)
        _selection = selection
        self.delete = delete

        let query = self.searchText
        _records = Query(
            filter: #Predicate<TranscriptRecord> { record in
                query.isEmpty
                    || record.title.localizedStandardContains(query)
                    || record.channel.localizedStandardContains(query)
                    || record.plainText.localizedStandardContains(query)
            },
            sort: \.createdAt,
            order: .reverse
        )
    }

    var body: some View {
        List(selection: $selection) {
            ForEach(HistoryGroup.grouped(records)) { group in
                Section(group.title) {
                    ForEach(group.records) { record in
                        HistoryRow(record: record, searchText: searchText)
                            .tag(record.persistentModelID)
                            .contextMenu { contextMenu(for: record) }
                    }
                }
            }
        }
        .onDeleteCommand {
            if let id = selection, let record = records.first(where: { $0.persistentModelID == id }) {
                delete(record)
            }
        }
        .overlay { emptyState }
        .animation(.smooth, value: records.map(\.persistentModelID))
    }

    @ViewBuilder
    private func contextMenu(for record: TranscriptRecord) -> some View {
        Link(destination: record.webpageURL) {
            Label("Open on YouTube", systemImage: "play.rectangle")
        }
        Button("Copy Video Link", systemImage: "link") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(record.webpageURL.absoluteString, forType: .string)
        }
        Divider()
        Button("Delete", systemImage: "trash", role: .destructive) { delete(record) }
    }

    @ViewBuilder
    private var emptyState: some View {
        if records.isEmpty {
            if searchText.isEmpty {
                ContentUnavailableView(
                    "No Transcripts Yet",
                    systemImage: "text.document",
                    description: Text("Transcripts you generate will appear here.")
                )
            } else {
                ContentUnavailableView.search(text: searchText)
            }
        }
    }
}

private struct HistoryRow: View {
    let record: TranscriptRecord
    let searchText: String

    /// When the search matched the transcript body rather than the title or channel, show where.
    private var snippet: String? {
        guard !searchText.isEmpty,
              record.title.range(of: searchText, options: [.caseInsensitive, .diacriticInsensitive]) == nil,
              record.channel.range(of: searchText, options: [.caseInsensitive, .diacriticInsensitive]) == nil
        else { return nil }
        return SearchSnippet.make(from: record.plainText, around: searchText)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            thumbnail
            VStack(alignment: .leading, spacing: 2) {
                Text(record.title)
                    .font(.body.weight(.medium))
                    .lineLimit(2)
                Text(record.channel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let snippet {
                    Text(snippet)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .italic()
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 3)
        .help(record.title)
    }

    private var thumbnail: some View {
        Color.secondary.opacity(0.15)
            .frame(width: 56, height: 32)
            .overlay {
                if let data = record.thumbnailData, let image = NSImage(data: data) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "play.rectangle")
                        .foregroundStyle(.tertiary)
                }
            }
            .clipShape(.rect(cornerRadius: 5))
            .padding(.top, 2)
    }
}

/// Records bucketed into "Today", "Yesterday", "Previous 7 Days", then by month.
struct HistoryGroup: Identifiable {
    let title: String
    var records: [TranscriptRecord]

    var id: String { title }

    static func grouped(_ records: [TranscriptRecord], now: Date = .now, calendar: Calendar = .current) -> [HistoryGroup] {
        var groups: [HistoryGroup] = []
        for record in records {
            let title = bucket(for: record.createdAt, now: now, calendar: calendar)
            if groups.last?.title == title {
                groups[groups.count - 1].records.append(record)
            } else {
                groups.append(HistoryGroup(title: title, records: [record]))
            }
        }
        return groups
    }

    static func bucket(for date: Date, now: Date, calendar: Calendar) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        if let weekAgo = calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: now)), date >= weekAgo {
            return "Previous 7 Days"
        }
        return date.formatted(.dateTime.month(.wide).year())
    }
}
