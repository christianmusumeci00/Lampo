import KeyboardShortcuts

/// The same key combination assigned to more than one command.
struct ShortcutConflict: Equatable, Identifiable {
    var shortcut: KeyboardShortcuts.Shortcut
    /// Names of the commands sharing it, in list order.
    var titles: [String]

    var id: String { "\(shortcut.carbonKeyCode)-\(shortcut.carbonModifiers)" }
}

/// Finds duplicate shortcuts. Pure, so it is unit-tested without touching UserDefaults.
enum ShortcutConflicts {
    struct Entry {
        var title: String
        var shortcut: KeyboardShortcuts.Shortcut?
    }

    static func find(_ entries: [Entry]) -> [ShortcutConflict] {
        var order: [KeyboardShortcuts.Shortcut] = []
        var titles: [KeyboardShortcuts.Shortcut: [String]] = [:]
        for entry in entries {
            guard let shortcut = entry.shortcut else { continue }
            if titles[shortcut] == nil { order.append(shortcut) }
            titles[shortcut, default: []].append(entry.title)
        }
        return order.compactMap { shortcut in
            guard let names = titles[shortcut], names.count > 1 else { return nil }
            return ShortcutConflict(shortcut: shortcut, titles: names)
        }
    }

    /// The title of the entry (other than `index`) that already uses `shortcut`.
    static func owner(of shortcut: KeyboardShortcuts.Shortcut, in entries: [Entry], excluding index: Int) -> String? {
        entries.enumerated().first { $0.offset != index && $0.element.shortcut == shortcut }?.element.title
    }
}
