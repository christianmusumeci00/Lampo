import AppKit
import Carbon.HIToolbox

enum Keystroke: Equatable, Sendable {
    case copy
    case paste
}

/// Posts synthetic shortcuts to the frontmost app. Abstracted for tests.
@MainActor
protocol KeystrokeSending: AnyObject {
    func post(_ keystroke: Keystroke)
    /// True while the user still holds ⌘ ⌥ ⇧ or ⌃ (e.g. right after pressing a hotkey).
    func modifiersHeld() -> Bool
}

@MainActor
final class SystemKeystrokeSender: KeystrokeSending {
    func post(_ keystroke: Keystroke) {
        // ANSI key codes: correct for QWERTY-family layouts (including Italian).
        let key = keystroke == .copy ? CGKeyCode(kVK_ANSI_C) : CGKeyCode(kVK_ANSI_V)
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cgAnnotatedSessionEventTap)
        up?.post(tap: .cgAnnotatedSessionEventTap)
    }

    func modifiersHeld() -> Bool {
        let flags = CGEventSource.flagsState(.combinedSessionState)
        return !flags.intersection([.maskCommand, .maskAlternate, .maskShift, .maskControl]).isEmpty
    }
}

/// Copy/paste through the clipboard while preserving the user's clipboard.
@MainActor
final class ClipboardBridge {
    typealias Sleeper = @MainActor (Duration) async -> Void

    private let pasteboard: any PasteboardClient
    private let keystrokes: any KeystrokeSending
    private let sleep: Sleeper
    let copyTimeout: Duration
    let restoreDelay: Duration

    init(
        pasteboard: any PasteboardClient,
        keystrokes: any KeystrokeSending,
        copyTimeout: Duration = .milliseconds(150),
        restoreDelay: Duration = .milliseconds(300),
        sleep: @escaping Sleeper = { try? await Task.sleep(for: $0) }
    ) {
        self.pasteboard = pasteboard
        self.keystrokes = keystrokes
        self.copyTimeout = copyTimeout
        self.restoreDelay = restoreDelay
        self.sleep = sleep
    }

    /// Simulates ⌘C, reads the copied text, then restores the original clipboard.
    /// Returns nil if the app didn't copy anything within the timeout.
    func copySelection() async -> String? {
        await waitForModifierRelease()
        let snapshot = pasteboard.snapshot()
        let before = pasteboard.changeCount
        keystrokes.post(.copy)

        let step = Duration.milliseconds(10)
        var waited = Duration.zero
        while pasteboard.changeCount == before && waited < copyTimeout {
            await sleep(step)
            waited += step
        }
        guard pasteboard.changeCount != before else { return nil }
        let text = pasteboard.string()
        pasteboard.restore(snapshot)
        return text
    }

    /// Puts `text` on the clipboard, simulates ⌘V (one undoable paste), then restores
    /// the original clipboard unless something else wrote to it in the meantime.
    func paste(_ text: String) async {
        await waitForModifierRelease()
        let snapshot = pasteboard.snapshot()
        pasteboard.setTransientString(text)
        let ours = pasteboard.changeCount
        keystrokes.post(.paste)
        await sleep(restoreDelay)
        if pasteboard.changeCount == ours {
            pasteboard.restore(snapshot)
        }
    }

    /// Synthetic ⌘C/⌘V must not merge with the ⌥⇧ still held from the hotkey.
    private func waitForModifierRelease() async {
        var waited = Duration.zero
        while keystrokes.modifiersHeld() && waited < .milliseconds(600) {
            await sleep(.milliseconds(15))
            waited += .milliseconds(15)
        }
    }
}
