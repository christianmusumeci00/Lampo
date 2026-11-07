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
    var contents: String?
    private(set) var changeCount = 0

    func string() -> String? { contents }

    func setString(_ string: String) {
        contents = string
        changeCount += 1
    }
}

@MainActor
final class MockHotkeyBackend: HotkeyBackend {
    private(set) var handlers: [KeyboardShortcuts.Name: @MainActor () -> Void] = [:]
    private(set) var disabled: Set<KeyboardShortcuts.Name> = []

    func onKeyDown(for name: KeyboardShortcuts.Name, action: @escaping @MainActor () -> Void) {
        handlers[name] = action
    }

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
