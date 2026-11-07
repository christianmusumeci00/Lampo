import Foundation
import Observation

/// One finished request: what was asked or rewritten, and the answer.
struct HistoryEntry: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var date: Date
    /// The action name, or "Panel" for questions asked in the panel.
    var source: String
    var input: String
    var output: String
    var route: ModelRoute
}

/// Optional local history (off by default). Kept only in Application Support/Lampo/history.json,
/// readable only by the user, never sent anywhere. Turning it off deletes it.
@MainActor
@Observable
final class HistoryStore {
    static let maxEntries = 200
    /// Long selections are cut so the file stays small.
    static let maxFieldLength = 4000

    private struct FileFormat: Codable {
        var version = 1
        var entries: [HistoryEntry]
    }

    /// Newest first.
    private(set) var entries: [HistoryEntry] = []
    @ObservationIgnored let fileURL: URL
    @ObservationIgnored private let isEnabled: () -> Bool
    @ObservationIgnored private let now: () -> Date

    static var defaultFileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Lampo", isDirectory: true).appendingPathComponent("history.json")
    }

    init(fileURL: URL = HistoryStore.defaultFileURL, isEnabled: @escaping () -> Bool, now: @escaping () -> Date = { .now }) {
        self.fileURL = fileURL
        self.isEnabled = isEnabled
        self.now = now
        if isEnabled() { load() }
    }

    /// Records a result when history is on; does nothing otherwise.
    func record(source: String, input: String, output: String, route: ModelRoute) {
        guard isEnabled() else { return }
        let answer = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty else { return }
        let entry = HistoryEntry(date: now(), source: source, input: Self.clip(input), output: Self.clip(answer), route: route)
        entries.insert(entry, at: 0)
        if entries.count > Self.maxEntries { entries.removeLast(entries.count - Self.maxEntries) }
        save()
    }

    func remove(_ id: HistoryEntry.ID) {
        entries.removeAll { $0.id == id }
        save()
    }

    /// Deletes every entry and the file.
    func clear() {
        entries = []
        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
            Log.app.info("history cleared")
        } catch {
            Log.app.error("history clear failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Call when the preference changes: on loads the file, off deletes it.
    func preferenceChanged() {
        if isEnabled() { load() } else { clear() }
    }

    func search(_ query: String) -> [HistoryEntry] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return entries }
        return entries.filter {
            $0.input.localizedStandardContains(needle) || $0.output.localizedStandardContains(needle)
                || $0.source.localizedStandardContains(needle)
        }
    }

    // MARK: Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { entries = []; return }
        do {
            entries = try JSONDecoder.history.decode(FileFormat.self, from: data).entries
        } catch {
            Log.app.error("history unreadable: \(error.localizedDescription, privacy: .public)")
            entries = []
        }
    }

    private func save() {
        do {
            let folder = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let data = try JSONEncoder.history.encode(FileFormat(entries: entries))
            try data.write(to: fileURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch {
            Log.app.error("history save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func clip(_ text: String) -> String {
        text.count > maxFieldLength ? String(text.prefix(maxFieldLength)) + "…" : text
    }
}

private extension JSONEncoder {
    static var history: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var history: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
