import Foundation
import Testing
@testable import Lampo

@MainActor
struct ActionStoreTests {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("LampoTests-\(UUID().uuidString)").appendingPathComponent("actions.json")

    func custom(_ name: String) -> LampoAction {
        LampoAction(name: name, symbol: "star", promptTemplate: "Do {{selection}}")
    }

    @Test func seedsBuiltInsOnFirstLaunch() {
        let store = ActionStore(fileURL: url)
        #expect(store.actions.map(\.id) == BuiltInActions.all.map(\.id))
        #expect(store.actions.allSatisfy { $0.isBuiltIn })
    }

    @Test func persistsEdits() {
        let store = ActionStore(fileURL: url)
        store.add(custom("Pirate"))
        var first = store.actions[0]
        first.promptTemplate = "Edited {{selection}}"
        store.update(first)
        store.move(fromOffsets: IndexSet(integer: store.actions.count - 1), toOffset: 0)

        let reloaded = ActionStore(fileURL: url)
        #expect(reloaded.actions.first?.name == "Pirate")
        #expect(reloaded.action(id: first.id)?.promptTemplate == "Edited {{selection}}")
        #expect(reloaded.actions.count == BuiltInActions.all.count + 1)
    }

    @Test func deletedBuiltInsStayDeleted() {
        let store = ActionStore(fileURL: url)
        store.delete(BuiltInActions.correctID)
        let reloaded = ActionStore(fileURL: url)
        #expect(reloaded.action(id: BuiltInActions.correctID) == nil)

        reloaded.restoreBuiltIns()
        #expect(reloaded.action(id: BuiltInActions.correctID) != nil)
    }

    @Test func newBuiltInsAreMergedOnUpdate() {
        let old = ActionStore(fileURL: url, builtIns: { Array(BuiltInActions.all.prefix(2)) })
        old.add(custom("Mine"))
        let updated = ActionStore(fileURL: url)
        #expect(updated.actions.count == BuiltInActions.all.count + 1)
        // New built-ins go after "Correct"; the user's own actions keep their place at the end.
        #expect(updated.actions[0].id == BuiltInActions.correctID)
        #expect(updated.actions[1].id == BuiltInActions.translateID)
        #expect(updated.actions.last?.name == "Mine")
    }

    @Test func duplicateCreatesCustomCopy() throws {
        let store = ActionStore(fileURL: url)
        let copy = try #require(store.duplicate(BuiltInActions.formalID))
        #expect(!copy.isBuiltIn)
        #expect(copy.id != BuiltInActions.formalID)
        let original = try #require(store.actions.firstIndex { $0.id == BuiltInActions.formalID })
        #expect(store.actions[original + 1].id == copy.id)
    }

    @Test func exportImportRoundTrip() throws {
        let store = ActionStore(fileURL: url)
        store.add(custom("Pirate"))
        let pirate = try #require(store.actions.last)
        let data = try store.exportData(ids: [pirate.id])

        let otherURL = url.deletingLastPathComponent().appendingPathComponent("other.json")
        let other = ActionStore(fileURL: otherURL)
        let count = try other.importData(data)
        #expect(count == 1)
        let imported = try #require(other.actions.last)
        #expect(imported.name == "Pirate")
        #expect(imported.id != pirate.id)
        #expect(!imported.isBuiltIn)
    }

    @Test func corruptFileFallsBackToBuiltIns() throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: url)
        #expect(ActionStore(fileURL: url).actions.count == BuiltInActions.all.count)
    }
}
