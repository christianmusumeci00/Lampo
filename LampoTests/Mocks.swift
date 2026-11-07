import ApplicationServices
import Foundation
import KeyboardShortcuts
@testable import Lampo

/// Scripted model: each `stream` call yields the given chunks (cumulative), optionally
/// pausing so tests can cancel mid-stream.
final class MockModelService: ModelService, @unchecked Sendable {
    var availabilityValue: ModelAvailability = .available
    var chunks: [String] = ["Hel", "Hello", "Hello!"]
    var failure: (any Error)?
    var delayPerChunk: Duration = .zero
    private(set) var conversations: [MockConversation] = []
    private(set) var makeConversationCalls = 0

    func availability() -> ModelAvailability { availabilityValue }
    func contextSize(for route: ModelRoute) async -> Int { 4096 }
    func tokenCount(_ text: String) async throws -> Int { text.split(separator: " ").count }

    func makeConversation(route: ModelRoute, instructions: String) throws -> any ModelConversation {
        makeConversationCalls += 1
        let conversation = MockConversation(route: route, owner: self)
        conversations.append(conversation)
        return conversation
    }
}

final class MockConversation: ModelConversation, @unchecked Sendable {
    let route: ModelRoute
    private weak var owner: MockModelService?
    private(set) var prompts: [String] = []
    private(set) var reasoning: [ReasoningEffort?] = []

    init(route: ModelRoute, owner: MockModelService) {
        self.route = route
        self.owner = owner
    }

    func prewarm() {}

    func stream(_ prompt: ModelPrompt, reasoning: ReasoningEffort?) -> AsyncThrowingStream<String, Error> {
        prompts.append(prompt.text)
        self.reasoning.append(reasoning)
        let chunks = owner?.chunks ?? []
        let failure = owner?.failure
        let delay = owner?.delayPerChunk ?? .zero
        return AsyncThrowingStream { continuation in
            let task = Task {
                for chunk in chunks {
                    if delay > .zero { try? await Task.sleep(for: delay) }
                    if Task.isCancelled { continuation.finish(throwing: CancellationError()); return }
                    continuation.yield(chunk)
                }
                if let failure { continuation.finish(throwing: failure) } else { continuation.finish() }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

@MainActor
final class MockPasteboard: PasteboardClient {
    static let stringType = "public.utf8-plain-text"
    var contents: String?
    /// Extra non-string data, to check full snapshots (e.g. an image the user copied).
    var extra: [String: Data] = [:]
    private(set) var changeCount = 0
    private(set) var transientWrites: [String] = []

    func string() -> String? { contents }

    func setString(_ string: String) {
        contents = string
        extra = [:]
        changeCount += 1
    }

    func setTransientString(_ string: String) {
        setString(string)
        transientWrites.append(string)
    }

    /// Another app writing to the clipboard.
    func externalWrite(_ string: String) { setString(string) }

    func snapshot() -> PasteboardSnapshot {
        var item = extra
        if let contents { item[Self.stringType] = Data(contents.utf8) }
        return PasteboardSnapshot(items: item.isEmpty ? [] : [item])
    }

    func restore(_ snapshot: PasteboardSnapshot) {
        changeCount += 1
        let item = snapshot.items.first ?? [:]
        contents = item[Self.stringType].map { String(decoding: $0, as: UTF8.self) }
        extra = item.filter { $0.key != Self.stringType }
    }
}

/// Simulates the frontmost app reacting to ⌘C / ⌘V.
@MainActor
final class MockKeystrokes: KeystrokeSending {
    let pasteboard: MockPasteboard
    /// What the app copies on ⌘C (nil: nothing selected, clipboard unchanged).
    var selectedText: String?
    var heldModifierChecks = 0
    private(set) var posted: [Keystroke] = []
    private(set) var pastedTexts: [String] = []

    init(pasteboard: MockPasteboard) { self.pasteboard = pasteboard }

    func post(_ keystroke: Keystroke) {
        posted.append(keystroke)
        switch keystroke {
        case .copy:
            if let selectedText { pasteboard.externalWrite(selectedText) }
        case .paste:
            pastedTexts.append(pasteboard.contents ?? "")
        }
    }

    func modifiersHeld() -> Bool {
        if heldModifierChecks > 0 {
            heldModifierChecks -= 1
            return true
        }
        return false
    }
}

@MainActor
final class MockAccessibility: AccessibilityClient {
    var isTrusted = true
    var selectedText: String?
    var bounds: CGRect?
    var replaceSucceeds = true
    private(set) var replacements: [String] = []

    func selection(in app: SourceApp) -> AXSelection? {
        guard isTrusted, let selectedText else { return nil }
        return AXSelection(text: selectedText, bounds: bounds,
                           element: AXElementHandle(AXUIElementCreateSystemWide()))
    }

    func focusedElementBounds(in app: SourceApp) -> CGRect? { nil }

    func replaceSelectedText(of element: AXElementHandle, with text: String) -> Bool {
        guard replaceSucceeds else { return false }
        replacements.append(text)
        return true
    }
}

@MainActor
final class MockPermissions: PermissionsChecking {
    var isAccessibilityGranted = true
    private(set) var requests = 0
    func requestAccessibility() { requests += 1 }
    func openAccessibilitySettings() {}
}

extension SourceApp {
    static let textEdit = SourceApp(name: "TextEdit", bundleIdentifier: "com.apple.TextEdit",
                                    processIdentifier: 4242, isElectron: false)
}

/// Clipboard bridge whose sleeps return immediately.
@MainActor
func makeBridge(_ pasteboard: MockPasteboard, _ keystrokes: MockKeystrokes) -> ClipboardBridge {
    ClipboardBridge(pasteboard: pasteboard, keystrokes: keystrokes, sleep: { _ in await Task.yield() })
}

@MainActor
final class MockHotkeyBackend: HotkeyBackend {
    private(set) var handlers: [KeyboardShortcuts.Name: @MainActor () -> Void] = [:]
    private(set) var disabled: Set<KeyboardShortcuts.Name> = []

    func onKeyDown(for name: KeyboardShortcuts.Name, action: @escaping @MainActor () -> Void) {
        handlers[name] = action
    }

    func removeHandler(for name: KeyboardShortcuts.Name) { handlers[name] = nil }
    func enable(_ names: [KeyboardShortcuts.Name]) { disabled.subtract(names) }
    func disable(_ names: [KeyboardShortcuts.Name]) { disabled.formUnion(names) }

    /// Simulates the system delivering a hotkey: only enabled names fire.
    func press(_ name: KeyboardShortcuts.Name) {
        guard !disabled.contains(name) else { return }
        handlers[name]?()
    }
}

/// A fresh, isolated UserDefaults suite per test.
func makeTestDefaults() -> UserDefaults {
    let name = "LampoTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

/// Manually advanced clock for session-timeout tests.
@MainActor
final class TestClock {
    var now = ContinuousClock.now
    func advance(_ duration: Duration) { now = now.advanced(by: duration) }
}
