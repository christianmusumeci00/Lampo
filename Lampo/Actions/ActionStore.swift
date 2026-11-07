import Foundation
import Observation

/// The user's actions, persisted as JSON in Application Support.
@MainActor
@Observable
final class ActionStore {
    private struct FileFormat: Codable {
        var version = 1
        var actions: [LampoAction]
        /// Built-ins the user deleted, so updates don't bring them back.
        var deletedBuiltIns: [UUID] = []
    }

    struct ExportFormat: Codable {
        var version = 1
        var actions: [LampoAction]
    }

    private(set) var actions: [LampoAction] = []
    @ObservationIgnored private var deletedBuiltIns: Set<UUID> = []
    @ObservationIgnored let fileURL: URL
    @ObservationIgnored private let builtIns: () -> [LampoAction]

    static var defaultFileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Lampo", isDirectory: true).appendingPathComponent("actions.json")
    }

    init(fileURL: URL = ActionStore.defaultFileURL, builtIns: @escaping () -> [LampoAction] = { BuiltInActions.all }) {
        self.fileURL = fileURL
        self.builtIns = builtIns
        load()
    }

    func action(id: UUID) -> LampoAction? { actions.first { $0.id == id } }

    /// Actions that work on the selection (Lens chips, Quick Actions menu).
    var selectionActions: [LampoAction] { actions.filter { $0.input == .selection } }

    // MARK: Editing

    func add(_ action: LampoAction) {
        actions.append(action)
        save()
    }

    func update(_ action: LampoAction) {
        guard let index = actions.firstIndex(where: { $0.id == action.id }) else { return }
        actions[index] = action
        save()
    }

    @discardableResult
    func duplicate(_ id: UUID) -> LampoAction? {
        guard let index = actions.firstIndex(where: { $0.id == id }) else { return nil }
        var copy = actions[index]
        copy.id = UUID()
        copy.isBuiltIn = false
        copy.name = String(localized: "\(copy.name) copy")
        actions.insert(copy, at: index + 1)
        save()
        return copy
    }

    func delete(_ id: UUID) {
        guard let index = actions.firstIndex(where: { $0.id == id }) else { return }
        if actions[index].isBuiltIn { deletedBuiltIns.insert(id) }
        actions.remove(at: index)
        save()
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        actions.move(fromOffsets: source, toOffset: destination)
        save()
    }

    /// Restores every built-in to its original definition, keeping custom actions.
    func restoreBuiltIns() {
        deletedBuiltIns = []
        let originals = builtIns()
        let customs = actions.filter { !$0.isBuiltIn }
        actions = originals + customs
        save()
    }

    // MARK: Import / export

    func exportData(ids: Set<UUID>? = nil) throws -> Data {
        let selected = ids.map { ids in actions.filter { ids.contains($0.id) } } ?? actions
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(ExportFormat(actions: selected))
    }

    /// Imports actions as new custom actions (fresh IDs), so nothing is overwritten.
    @discardableResult
    func importData(_ data: Data) throws -> Int {
        let decoded = try JSONDecoder().decode(ExportFormat.self, from: data)
        let imported = decoded.actions.map { action -> LampoAction in
            var copy = action
            copy.id = UUID()
            copy.isBuiltIn = false
            return copy
        }
        actions.append(contentsOf: imported)
        save()
        return imported.count
    }

    // MARK: Persistence

    private func load() {
        let originals = builtIns()
        guard let data = try? Data(contentsOf: fileURL),
              let file = try? JSONDecoder().decode(FileFormat.self, from: data) else {
            actions = originals
            return
        }
        deletedBuiltIns = Set(file.deletedBuiltIns)
        actions = file.actions
        // Built-ins added in a newer version of Lampo.
        let known = Set(actions.map(\.id)).union(deletedBuiltIns)
        let missing = originals.filter { !known.contains($0.id) }
        if !missing.isEmpty {
            actions.append(contentsOf: missing)
            save()
        }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(FileFormat(actions: actions, deletedBuiltIns: Array(deletedBuiltIns).sorted { $0.uuidString < $1.uuidString }))
            try data.write(to: fileURL, options: .atomic)
        } catch {
            Log.app.error("couldn't save actions: \(error.localizedDescription, privacy: .public)")
        }
    }
}
