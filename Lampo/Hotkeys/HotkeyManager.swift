import AppKit
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Opens or closes the Glass panel. Default ⌥Space.
    static let togglePanel = Self("togglePanel", initial: .init(.space, modifiers: [.option]))
}

/// The global-hotkey system, abstracted for tests.
@MainActor
protocol HotkeyBackend: AnyObject {
    func onKeyDown(for name: KeyboardShortcuts.Name, action: @escaping @MainActor () -> Void)
    func removeHandler(for name: KeyboardShortcuts.Name)
    func enable(_ names: [KeyboardShortcuts.Name])
    func disable(_ names: [KeyboardShortcuts.Name])
}

@MainActor
final class KeyboardShortcutsBackend: HotkeyBackend {
    func onKeyDown(for name: KeyboardShortcuts.Name, action: @escaping @MainActor () -> Void) {
        KeyboardShortcuts.onKeyDown(for: name) { action() }
    }

    func removeHandler(for name: KeyboardShortcuts.Name) { KeyboardShortcuts.removeHandler(for: name) }
    func enable(_ names: [KeyboardShortcuts.Name]) { KeyboardShortcuts.enable(names) }
    func disable(_ names: [KeyboardShortcuts.Name]) { KeyboardShortcuts.disable(names) }
}

/// Owns every global hotkey Lampo registers. Disabling unregisters all of them,
/// so no shortcut reaches Lampo while it is turned off.
@MainActor
final class HotkeyManager {
    private let backend: HotkeyBackend
    private(set) var registeredNames: [KeyboardShortcuts.Name] = []
    private(set) var isEnabled: Bool

    init(backend: HotkeyBackend = KeyboardShortcutsBackend(), isEnabled: Bool) {
        self.backend = backend
        self.isEnabled = isEnabled
    }

    func register(_ name: KeyboardShortcuts.Name, action: @escaping @MainActor () -> Void) {
        guard !registeredNames.contains(name) else { return }
        registeredNames.append(name)
        backend.onKeyDown(for: name, action: action)
        if !isEnabled { backend.disable([name]) }
    }

    func unregister(_ name: KeyboardShortcuts.Name) {
        guard let index = registeredNames.firstIndex(of: name) else { return }
        registeredNames.remove(at: index)
        backend.removeHandler(for: name)
    }

    /// Registers exactly `names` among names with `prefix`, removing stale ones
    /// (e.g. deleted actions) and adding new ones.
    func sync(_ names: [KeyboardShortcuts.Name], prefix: String,
              action: @escaping @MainActor (KeyboardShortcuts.Name) -> Void) {
        let wanted = Set(names.map(\.rawValue))
        for name in registeredNames where name.rawValue.hasPrefix(prefix) && !wanted.contains(name.rawValue) {
            unregister(name)
        }
        for name in names where !registeredNames.contains(where: { $0.rawValue == name.rawValue }) {
            register(name) { action(name) }
        }
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if enabled {
            backend.enable(registeredNames)
        } else {
            backend.disable(registeredNames)
        }
        Log.hotkeys.info("hotkeys \(enabled ? "enabled" : "disabled", privacy: .public) (\(self.registeredNames.count) names)")
    }
}
