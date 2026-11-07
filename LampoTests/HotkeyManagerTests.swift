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
}
