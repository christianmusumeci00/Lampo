import AppKit
import SwiftUI

/// The local history, newest first, with search and copy.
struct HistoryView: View {
    let history: HistoryStore
    let onClose: () -> Void
    @State private var query = ""
    @State private var selection: HistoryEntry.ID?

    private var results: [HistoryEntry] { history.search(query) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("History").font(.headline)
                Spacer()
                TextField("Search", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
            }
            .padding(12)
            Divider()
            if results.isEmpty {
                ContentUnavailableView(query.isEmpty ? "No history yet" : "No results",
                                       systemImage: "clock.arrow.circlepath")
                    .frame(maxHeight: .infinity)
            } else {
                List(results, selection: $selection) { entry in
                    HistoryRow(entry: entry)
                        .tag(entry.id)
                        .contextMenu {
                            Button("Copy Answer") { copy(entry.output) }
                            Button("Copy Question") { copy(entry.input) }
                            Divider()
                            Button("Delete", role: .destructive) { history.remove(entry.id) }
                        }
                }
                .listStyle(.inset)
            }
            Divider()
            HStack {
                Text("\(history.entries.count) saved")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Copy Answer") {
                    if let entry = results.first(where: { $0.id == selection }) { copy(entry.output) }
                }
                .disabled(selection == nil)
                Button("Done", action: onClose)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 600, height: 480)
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

private struct HistoryRow: View {
    let entry: HistoryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(entry.source).font(.system(size: 12, weight: .semibold))
                Image(systemName: entry.route == .onDevice ? "lock.fill" : "cloud")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(Text(entry.route == .onDevice ? "On Mac" : "Private Cloud"))
                Spacer()
                Text(entry.date, format: .dateTime.day().month().hour().minute())
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Text(entry.input)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(entry.output)
                .font(.system(size: 13))
                .lineLimit(3)
        }
        .padding(.vertical, 4)
    }
}
