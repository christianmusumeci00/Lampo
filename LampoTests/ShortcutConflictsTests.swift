import Foundation
import KeyboardShortcuts
import Testing
@testable import Lampo

@MainActor
struct ShortcutConflictsTests {
    let c = KeyboardShortcuts.Shortcut(.c, modifiers: [.option, .shift])
    let f = KeyboardShortcuts.Shortcut(.f, modifiers: [.option, .shift])
    let space = KeyboardShortcuts.Shortcut(.space, modifiers: [.option])

    @Test func findsTheSameCombinationAssignedTwice() {
        let entries = [
            ShortcutConflicts.Entry(title: "Open Lampo", shortcut: space),
            ShortcutConflicts.Entry(title: "Correct", shortcut: c),
            ShortcutConflicts.Entry(title: "More formal", shortcut: f),
            ShortcutConflicts.Entry(title: "My action", shortcut: c),
            ShortcutConflicts.Entry(title: "Unassigned", shortcut: nil),
            ShortcutConflicts.Entry(title: "Other", shortcut: nil),
        ]
        let conflicts = ShortcutConflicts.find(entries)
        #expect(conflicts.count == 1)
        #expect(conflicts.first?.shortcut == c)
        #expect(conflicts.first?.titles == ["Correct", "My action"])
    }

    @Test func noConflictsWhenAllDiffer() {
        let entries = [
            ShortcutConflicts.Entry(title: "A", shortcut: c),
            ShortcutConflicts.Entry(title: "B", shortcut: f),
        ]
        #expect(ShortcutConflicts.find(entries).isEmpty)
    }

    @Test func ownerIgnoresTheEntryBeingRecorded() {
        let entries = [
            ShortcutConflicts.Entry(title: "Open Lampo", shortcut: space),
            ShortcutConflicts.Entry(title: "Correct", shortcut: c),
        ]
        #expect(ShortcutConflicts.owner(of: c, in: entries, excluding: 0) == "Correct")
        #expect(ShortcutConflicts.owner(of: c, in: entries, excluding: 1) == nil)
        #expect(ShortcutConflicts.owner(of: f, in: entries, excluding: 0) == nil)
    }
}

@MainActor
struct ActionStoreHotkeySyncTests {
    @Test func notifiesOnlyWhenActionsAreAddedOrRemoved() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("lampo-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = ActionStore(fileURL: url)
        var calls = 0
        store.onActionsAddedOrRemoved = { calls += 1 }

        var first = try #require(store.actions.first)
        first.name = "Renamed"
        store.update(first)
        #expect(calls == 0)

        let added = LampoAction(name: "Mine", symbol: "sparkles", promptTemplate: "Do it")
        store.add(added)
        #expect(calls == 1)
        store.move(fromOffsets: [0], toOffset: 2)
        #expect(calls == 1)
        store.delete(added.id)
        #expect(calls == 2)
    }

    @Test func askTheScreenIsMergedIntoExistingFiles() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("lampo-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        // A file saved before "Ask the screen" existed.
        let old = ActionStore(fileURL: url, builtIns: { BuiltInActions.all.filter { $0.id != BuiltInActions.askScreenID } })
        old.add(LampoAction(name: "Mine", symbol: "sparkles", promptTemplate: "x"))
        let reloaded = ActionStore(fileURL: url)
        #expect(reloaded.action(id: BuiltInActions.askScreenID) != nil)
        #expect(reloaded.actions.contains { $0.name == "Mine" })
    }
}
