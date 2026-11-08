import ApplicationServices
import CoreGraphics
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
    var contextSizeValue = 4096
    /// When set, `tokenCount` throws (as it does for images on macOS 27).
    var tokenCountFails = false
    private(set) var conversations: [MockConversation] = []
    private(set) var makeConversationCalls = 0

    func availability() -> ModelAvailability { availabilityValue }
    func contextSize(for route: ModelRoute) async -> Int { contextSizeValue }
    /// One token per whitespace-separated word.
    func tokenCount(_ text: String) async throws -> Int {
        if tokenCountFails { throw ModelError.other }
        return text.split(whereSeparator: { $0.isWhitespace }).count
    }

    var extracted = ExtractedDetails()
    var extractionFailure: (any Error)?
    private(set) var extractions: [(text: String, kind: DraftKind)] = []

    func extractDetails(from text: String, kind: DraftKind) async throws -> ExtractedDetails {
        extractions.append((text, kind))
        if let extractionFailure { throw extractionFailure }
        return extracted
    }

    /// nil: split like the model would on new lines, semicolons and commas.
    var splitResult: [String]?
    var contact = ContactDraft()
    var table = ExtractedTable()
    var tasks: [String] = []
    private(set) var extractCalls: [String] = []

    func splitItems(_ text: String) async throws -> [String] {
        extractCalls.append("split")
        if let extractionFailure { throw extractionFailure }
        return splitResult ?? ListSplitter.segments(of: text, splittingCommas: true)
    }

    func extractContact(from text: String) async throws -> ContactDraft {
        extractCalls.append("contact")
        if let extractionFailure { throw extractionFailure }
        return contact
    }

    func extractTable(from text: String) async throws -> ExtractedTable {
        extractCalls.append("table")
        if let extractionFailure { throw extractionFailure }
        return table
    }

    func extractTasks(from text: String) async throws -> [String] {
        extractCalls.append("tasks")
        if let extractionFailure { throw extractionFailure }
        return tasks
    }

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
    private(set) var imageCounts: [Int] = []
    private(set) var reasoning: [ReasoningEffort?] = []

    init(route: ModelRoute, owner: MockModelService) {
        self.route = route
        self.owner = owner
    }

    func prewarm() {}

    func stream(_ prompt: ModelPrompt, reasoning: ReasoningEffort?) -> AsyncThrowingStream<String, Error> {
        prompts.append(prompt.text)
        imageCounts.append(prompt.images.count)
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
    var isScreenRecordingGranted = true
    private(set) var requests = 0
    private(set) var screenRequests = 0
    func requestAccessibility() { requests += 1 }
    func openAccessibilitySettings() {}
    /// "request" / "open settings", in order.
    private(set) var screenEvents: [String] = []
    func requestScreenRecording() async {
        screenRequests += 1
        await Task.yield()
        screenEvents.append("request")
    }
    func openScreenRecordingSettings() { screenEvents.append("open settings") }
    var isSystemPrivacyAlertShowing = false
    func revealApp() {}
}

/// Returns a 1×1 image for the front window, or fails.
final class MockScreenCapture: ScreenCapturing, @unchecked Sendable {
    var error: ScreenCaptureError?
    /// Text "recognized" in the window.
    var text: String?
    private(set) var captures = 0

    func captureFrontWindow(of app: SourceApp) async throws -> WindowCapture {
        captures += 1
        if let error { throw error }
        return WindowCapture(image: Self.image, app: app, title: "main.swift", text: text)
    }

    static let image: CGImage = {
        let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return context.makeImage()!
    }()
}

extension SourceApp {
    static let terminal = SourceApp(name: "Terminal", bundleIdentifier: "com.apple.Terminal",
                                    processIdentifier: 4343, isElectron: false)
}

/// Waits (yielding) until `condition` holds, up to ~2 s.
@MainActor
func waitUntil(_ condition: () -> Bool) async {
    for _ in 0..<400 where !condition() {
        try? await Task.sleep(for: .milliseconds(5))
    }
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

    private(set) var keyUpHandlers: [KeyboardShortcuts.Name: @MainActor () -> Void] = [:]

    func onKeyDown(for name: KeyboardShortcuts.Name, action: @escaping @MainActor () -> Void) {
        handlers[name] = action
    }

    func onKeyUp(for name: KeyboardShortcuts.Name, action: @escaping @MainActor () -> Void) {
        keyUpHandlers[name] = action
    }

    func removeHandler(for name: KeyboardShortcuts.Name) {
        handlers[name] = nil
        keyUpHandlers[name] = nil
    }
    func enable(_ names: [KeyboardShortcuts.Name]) { disabled.subtract(names) }
    func disable(_ names: [KeyboardShortcuts.Name]) { disabled.formUnion(names) }

    /// Simulates the system delivering a hotkey: only enabled names fire.
    func press(_ name: KeyboardShortcuts.Name) {
        guard !disabled.contains(name) else { return }
        handlers[name]?()
    }

    func release(_ name: KeyboardShortcuts.Name) {
        guard !disabled.contains(name) else { return }
        keyUpHandlers[name]?()
    }
}

/// A fresh, isolated UserDefaults suite per test.
func makeTestDefaults() -> UserDefaults {
    TestDefaultsCleanup.install
    let name = "LampoTests.\(UUID().uuidString)"
    TestDefaultsCleanup.track(name)
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

/// Each test's UserDefaults suite is a plist in ~/Library/Preferences. They're removed when the
/// run ends, and leftovers of runs that were killed are removed at the start of the next one.
enum TestDefaultsCleanup {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var names: [String] = []

    static let install: Void = {
        removeLeftovers()
        atexit { TestDefaultsCleanup.removeAll() }
    }()

    static func track(_ name: String) {
        lock.withLock { names.append(name) }
    }

    static func removeAll() {
        let all = lock.withLock { names }
        for name in all { UserDefaults.standard.removePersistentDomain(forName: name) }
    }

    private static func removeLeftovers() {
        let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Preferences")
        let files = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        for file in files where file.hasPrefix("LampoTests.") && file.hasSuffix(".plist") {
            let name = String(file.dropLast(".plist".count))
            UserDefaults.standard.removePersistentDomain(forName: name)
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(file))
        }
    }
}

/// Manually advanced clock for session-timeout tests.
@MainActor
final class TestClock {
    var now = ContinuousClock.now
    func advance(_ duration: Duration) { now = now.advanced(by: duration) }
}

/// Records what would be written to Calendar/Reminders.
@MainActor
final class MockCalendarWriter: CalendarWriting {
    var accessValue: CalendarAccess = .granted
    /// What the system prompt answers when access is not determined.
    var grantsOnRequest = true
    var saveFailure: CalendarWriteError?
    /// Saves this many items, then fails with `saveFailure` (or `.saveFailed`).
    var failAfter: Int?
    private(set) var accessRequests: [DraftKind] = []
    private(set) var savedEvents: [CalendarEventDraft] = []
    private(set) var savedReminders: [ReminderDraft] = []
    private(set) var openedSettings: [DraftKind] = []

    func access(for kind: DraftKind) -> CalendarAccess { accessValue }

    func requestAccess(for kind: DraftKind) async -> Bool {
        accessRequests.append(kind)
        accessValue = grantsOnRequest ? .granted : .denied
        return grantsOnRequest
    }

    private func check() throws {
        if let failAfter {
            if savedEvents.count + savedReminders.count >= failAfter { throw saveFailure ?? .saveFailed }
        } else if let saveFailure {
            throw saveFailure
        }
    }

    func save(_ draft: CalendarEventDraft) throws {
        try check()
        savedEvents.append(draft)
    }

    func save(_ draft: ReminderDraft) throws {
        try check()
        savedReminders.append(draft)
    }

    func openSettings(for kind: DraftKind) { openedSettings.append(kind) }
    func openApp(for kind: DraftKind, at date: Date?) {}
}

/// A Gregorian calendar in Rome, and a date in it, for date-resolution tests.
enum TestDates {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Rome")!
        calendar.locale = Locale(identifier: "it_IT")
        return calendar
    }()

    static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    /// Sunday 8 November 2026, 10:00 in Rome.
    static let sundayMorning = date(2026, 11, 8, 10)
}

/// Upper-cases each line, tagged with the target: "[en] CIAO".
final class MockTranslator: Translating, @unchecked Sendable {
    var failure: (any Error)?
    var languages = ["de", "en", "fr", "it"]
    private(set) var calls: [(lines: [String], pair: TranslationPair)] = []

    func translate(_ lines: [String], pair: TranslationPair) async throws -> [String] {
        calls.append((lines, pair))
        if let failure { throw failure }
        return lines.map { "[\(pair.target)] \($0.uppercased())" }
    }

    func supportedLanguages() async -> [String] { languages }
}

/// Hands back `transcript` on stop; records starts, stops and cancels.
@MainActor
final class MockDictationEngine: DictationEngine {
    var microphoneAccess: MicrophoneAccess = .granted
    var grantsMicrophone = true
    var readinessValue: DictationReadiness = .ready
    var transcript = "ehm allora domani non vengo"
    var startFailure: (any Error)?
    private(set) var started: [String] = []
    private(set) var stops = 0
    private(set) var cancels = 0
    private(set) var downloads: [String] = []
    private var continuation: AsyncStream<DictationUpdate>.Continuation?

    func requestMicrophone() async -> Bool {
        microphoneAccess = grantsMicrophone ? .granted : .denied
        return grantsMicrophone
    }

    func readiness(for language: String) async -> DictationReadiness { readinessValue }
    func downloadModel(for language: String) async throws { downloads.append(language) }

    func start(language: String) async throws -> AsyncStream<DictationUpdate> {
        if let startFailure { throw startFailure }
        started.append(language)
        let (stream, continuation) = AsyncStream<DictationUpdate>.makeStream()
        self.continuation = continuation
        continuation.yield(.level(0.5))
        continuation.yield(.text("ehm allora"))
        return stream
    }

    func stop() async throws -> String {
        stops += 1
        continuation?.finish()
        return transcript
    }

    func cancel() async {
        cancels += 1
        continuation?.finish()
    }
}
