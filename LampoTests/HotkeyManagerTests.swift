import Foundation
import KeyboardShortcuts
import Testing
@testable import Lampo

@MainActor
struct HotkeyManagerTests {
    @Test func disablingSilencesEveryHotkey() {
        let backend = MockHotkeyBackend()
        let manager = HotkeyManager(backend: backend, isEnabled: true)
        var fired = 0
        manager.register(.togglePanel) { fired += 1 }

        backend.press(.togglePanel)
        #expect(fired == 1)

        manager.setEnabled(false)
        backend.press(.togglePanel)
        #expect(fired == 1)
        #expect(backend.disabled.contains(.togglePanel))

        manager.setEnabled(true)
        backend.press(.togglePanel)
        #expect(fired == 2)
    }

    @Test func registeringWhileDisabledStaysDisabled() {
        let backend = MockHotkeyBackend()
        let manager = HotkeyManager(backend: backend, isEnabled: false)
        var fired = false
        manager.register(.togglePanel) { fired = true }
        backend.press(.togglePanel)
        #expect(!fired)
    }

    @Test func appStateToggleDisablesHotkeys() {
        let backend = MockHotkeyBackend()
        let state = AppState(preferences: Preferences(defaults: makeTestDefaults()),
                             modelService: MockModelService(), hotkeyBackend: backend)
        state.hotkeys.register(.togglePanel) {}
        state.isEnabled = false
        #expect(backend.disabled.contains(.togglePanel))
        #expect(!state.preferences.isEnabled)
        state.isEnabled = true
        #expect(backend.disabled.isEmpty)
    }

    @Test func syncAddsAndRemovesActionHotkeys() {
        let backend = MockHotkeyBackend()
        let manager = HotkeyManager(backend: backend, isEnabled: true)
        let a = KeyboardShortcuts.Name("action-test-a")
        let b = KeyboardShortcuts.Name("action-test-b")
        var fired: [String] = []
        manager.register(.togglePanel) {}
        manager.sync([a, b], prefix: "action-") { fired.append($0.rawValue) }
        backend.press(a)
        #expect(fired == ["action-test-a"])

        manager.sync([b], prefix: "action-") { fired.append($0.rawValue) }
        backend.press(a)
        backend.press(b)
        #expect(fired == ["action-test-a", "action-test-b"])
        #expect(manager.registeredNames.map(\.rawValue) == ["togglePanel", "action-test-b"])
    }
}

@MainActor
struct PanelShortcutMigrationTests {
    let legacy = PanelShortcutMigration.legacy
    let current = PanelShortcutMigration.current
    let custom = KeyboardShortcuts.Shortcut(.l, modifiers: [.command, .option])

    private func freshDefaults() -> UserDefaults {
        let name = "PanelShortcutMigrationTests-\(UUID().uuidString)"
        return UserDefaults(suiteName: name)!
    }

    @Test func newDefaultIsOptionShiftSpace() {
        #expect(KeyboardShortcuts.Name.togglePanel.initialShortcut == current)
        #expect(current != legacy)
    }

    @Test func movesTheOldDefaultOnce() {
        let defaults = freshDefaults()
        var stored: KeyboardShortcuts.Shortcut? = legacy
        PanelShortcutMigration.run(defaults: defaults, taken: [], get: { stored }, set: { stored = $0 })
        #expect(stored == current)

        // The user deliberately goes back to ⌥Space: a later launch leaves it alone.
        stored = legacy
        PanelShortcutMigration.run(defaults: defaults, taken: [], get: { stored }, set: { stored = $0 })
        #expect(stored == legacy)
    }

    @Test func keepsAShortcutTheUserChose() {
        #expect(PanelShortcutMigration.replacement(for: custom, taken: []) == nil)
        #expect(PanelShortcutMigration.replacement(for: nil, taken: []) == nil)
        #expect(PanelShortcutMigration.replacement(for: current, taken: []) == nil)
    }

    @Test func leavesTheOldDefaultWhenTheNewOneIsTaken() {
        #expect(PanelShortcutMigration.replacement(for: legacy, taken: [nil, current]) == nil)
        #expect(PanelShortcutMigration.replacement(for: legacy, taken: [nil, custom]) == current)
    }
}
