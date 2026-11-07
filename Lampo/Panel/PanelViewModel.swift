import AppKit
import Observation
import SwiftUI

/// One question/answer exchange shown in the panel.
struct ConversationTurn: Identifiable, Equatable {
    enum State: Equatable {
        case streaming
        case done
        case cancelled
        case failed(String)
    }

    enum Kind: Equatable {
        case model
        case calculation
    }

    let id = UUID()
    var question: String
    var answer: String = ""
    var route: ModelRoute
    var kind: Kind
    var state: State
    /// Short description of the context sent with this question ("Selection · 12 words").
    var contextSummary: String?
    /// True for "Go deeper" follow-ups, whose prompt is synthetic.
    var isGoDeeper = false
    /// The context was too long and only an excerpt was sent.
    var wasTruncated = false

    var isFinished: Bool { state != .streaming }
}

/// A message under the input row: a missing permission (with a button) or a short error.
enum PanelNotice: Equatable {
    case permission(PermissionKind)
    case message(String)
}

/// What a question is made of, before it is fitted to the context window.
struct PromptParts {
    var question: String
    var selection: String?
    var app: String?
    var clipboard: String?
    var window: WindowCapture?
    /// English name of the answer language, stated with the context.
    var answerLanguage: String?

    var hasText: Bool { selection != nil || clipboard != nil }

    /// The untruncated prompt.
    var full: ModelPrompt { compose(selection: selection, clipboard: clipboard) }

    /// The prompt with the given (possibly cut) context texts.
    func compose(selection: String?, clipboard: String?) -> ModelPrompt {
        let block = SystemInstructions.contextBlock(
            selection: selection, app: app, clipboard: clipboard,
            window: window.map { (app: $0.app.name, title: $0.title) },
            answerLanguage: answerLanguage)
        let text: String
        if block.isEmpty {
            text = question
        } else {
            text = question.isEmpty ? block : block + "\n\n" + question
        }
        return ModelPrompt(text, images: window.map { [$0.image] } ?? [])
    }
}

/// State and behaviour of the Glass panel. UI-free, so it is unit-tested with mocks.
@MainActor
@Observable
final class PanelViewModel {
    /// The conversation is forgotten after this much inactivity.
    static let sessionTimeout: Duration = .seconds(5 * 60)

    var query = ""
    private(set) var turns: [ConversationTurn] = []
    /// Chips shown in the input row; sent with the next question.
    private(set) var contextItems: [ContextItem] = []
    private(set) var isAccessibilityGranted = true
    private(set) var availability: ModelAvailability = .unknown
    /// Brief confirmation shown in the action bar ("Copied").
    private(set) var flash: String?
    /// Incremented to ask the view to focus the input field.
    private(set) var focusRequest = 0
    private(set) var notice: PanelNotice?
    /// A window screenshot is being taken (⌘⇧S).
    private(set) var isCapturingWindow = false

    @ObservationIgnored private let model: any ModelService
    @ObservationIgnored private let preferences: Preferences
    @ObservationIgnored private let pasteboard: any PasteboardClient
    @ObservationIgnored private let screenCapture: any ScreenCapturing
    @ObservationIgnored private let budget: ContextBudget
    @ObservationIgnored private let clock: () -> ContinuousClock.Instant
    @ObservationIgnored private var conversation: (any ModelConversation)?
    @ObservationIgnored private(set) var generationTask: Task<Void, Never>?
    @ObservationIgnored private var lastActivity: ContinuousClock.Instant
    @ObservationIgnored private var flashTask: Task<Void, Never>?
    @ObservationIgnored private var captureTask: Task<Void, Never>?
    /// Untruncated parts of each model turn, for "Think harder".
    @ObservationIgnored private var partsByTurn: [UUID: PromptParts] = [:]
    /// Text actually sent for each turn, to estimate the history's share of the window.
    @ObservationIgnored private var sentTextByTurn: [UUID: String] = [:]

    /// The selection the current conversation is about; "Insert" replaces it.
    @ObservationIgnored private(set) var activeSelection: SelectionContext?

    /// Called after a successful copy when "close after copy" is on.
    @ObservationIgnored var onRequestClose: (() -> Void)?
    /// Called by "Insert ⌘↩" with the answer and the selection to replace (if any).
    @ObservationIgnored var onInsert: ((String, SelectionContext?) -> Void)?
    /// Called by the "Allow…" button of a permission notice.
    @ObservationIgnored var onGrantPermission: ((PermissionKind) -> Void)?

    init(
        model: any ModelService,
        preferences: Preferences,
        pasteboard: any PasteboardClient,
        screenCapture: any ScreenCapturing = ScreenCaptureService(),
        clock: @escaping () -> ContinuousClock.Instant = { .now }
    ) {
        self.model = model
        self.preferences = preferences
        self.pasteboard = pasteboard
        self.screenCapture = screenCapture
        self.budget = ContextBudget(model: model)
        self.clock = clock
        self.lastActivity = clock()
    }

    // MARK: Derived state

    var currentTurn: ConversationTurn? { turns.last }
    var previousTurns: ArraySlice<ConversationTurn> { turns.dropLast() }
    var isGenerating: Bool { currentTurn?.state == .streaming }
    var hasContent: Bool { !turns.isEmpty }
    var canCopy: Bool { !(currentTurn?.answer.isEmpty ?? true) }
    var canFollowUp: Bool { conversation != nil && !isGenerating && currentTurn?.kind == .model }
    var canInsert: Bool { canCopy && !isGenerating }
    var canThinkHarder: Bool { preferences.routingPolicy.allowsPrivateCloud && !isGenerating && currentTurn != nil }
    var hasWindowContext: Bool { contextItems.contains { if case .window = $0 { true } else { false } } }

    // MARK: Lifecycle

    /// Called every time the panel is shown.
    func panelWillAppear() {
        notice = nil
        refreshAvailability()
        if clock() - lastActivity > Self.sessionTimeout {
            resetConversation()
            lastActivity = clock()
        }
        if availability.isAvailable && conversation == nil {
            ensureConversation()?.prewarm()
        }
        focusRequest += 1
    }

    func refreshAvailability() {
        availability = model.availability()
    }

    func setAccessibilityGranted(_ granted: Bool) {
        isAccessibilityGranted = granted
    }

    // MARK: Context chips

    func setContext(_ items: [ContextItem]) {
        contextItems = items
    }

    func addContext(_ item: ContextItem) {
        contextItems.removeAll { $0.id == item.id || ($0.isSelection && item.isSelection) }
        contextItems.append(item)
    }

    func removeContext(id: String) {
        contextItems.removeAll { $0.id == id }
    }

    /// Backspace in an empty field removes the last chip. Returns true if one was removed.
    @discardableResult
    func removeLastContextIfQueryEmpty() -> Bool {
        guard query.isEmpty, !contextItems.isEmpty else { return false }
        contextItems.removeLast()
        return true
    }

    /// ⌘⇧S: attaches a screenshot of `app`'s front window, or removes it if already attached.
    func toggleWindow(from app: SourceApp?, permitted: Bool) {
        if hasWindowContext {
            removeContext(id: "window")
            return
        }
        guard permitted else {
            notice = .permission(.screenRecording)
            return
        }
        guard let app else {
            notice = .message(ScreenCaptureError.noWindow.localizedDescription)
            return
        }
        guard !isCapturingWindow else { return }
        isCapturingWindow = true
        notice = nil
        captureTask = Task { [weak self, screenCapture] in
            do {
                let capture = try await screenCapture.captureFrontWindow(of: app)
                self?.addContext(.window(capture))
            } catch let error as ScreenCaptureError {
                self?.notice = error == .permissionDenied ? .permission(.screenRecording) : .message(error.localizedDescription)
            } catch {
                self?.notice = .message(ScreenCaptureError.failed.localizedDescription)
            }
            self?.isCapturingWindow = false
            self?.focusRequest += 1
        }
    }

    /// "Ask the screen": a fresh conversation about a captured window, waiting for the question.
    func prepareScreenQuestion(_ capture: WindowCapture) {
        resetConversation()
        contextItems = [.window(capture)]
    }

    func showNotice(_ notice: PanelNotice?) {
        self.notice = notice
    }

    func grantPermission(_ kind: PermissionKind) {
        onGrantPermission?(kind)
    }

    // MARK: Output

    func insertCurrentAnswer() {
        guard canInsert, let answer = currentTurn?.answer else { return }
        onInsert?(answer, activeSelection)
    }

    func resetConversation() {
        cancel()
        turns = []
        conversation = nil
        contextItems = []
        activeSelection = nil
        partsByTurn = [:]
        sentTextByTurn = [:]
        query = ""
        notice = nil
        focusRequest += 1
    }

    // MARK: Actions

    func submit() {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isGenerating else { return }
        query = ""
        notice = nil
        touch()

        if contextItems.isEmpty, let result = Calculator.evaluate(text) {
            let answer: String
            switch result {
            case .success(let value): answer = Calculator.format(value)
            case .failure: answer = String(localized: "Undefined")
            }
            turns.append(ConversationTurn(question: text, answer: answer, route: .onDevice, kind: .calculation, state: .done))
            return
        }

        let (parts, summary) = consumeContext(question: text)
        ask(Request(displayedQuestion: text, route: .onDevice, contextSummary: summary, parts: parts))
    }

    /// Runs an action whose result belongs in the panel (e.g. "Explain"). `prompt` is already
    /// rendered and fitted by `ActionRunner`; a window chip adds its screenshot.
    func runAction(_ action: LampoAction, prompt: String, wasTruncated: Bool = false, contextItems items: [ContextItem]) {
        resetConversation()
        contextItems = items
        let (parts, summary) = consumeContext(question: "")
        touch()
        ask(Request(displayedQuestion: action.name, route: action.route, contextSummary: summary,
                    parts: PromptParts(question: prompt, window: parts.window),
                    wasTruncated: wasTruncated, fitsContext: false))
    }

    /// Collects the chips into prompt parts (then clears them: the session now has the context).
    private func consumeContext(question: String) -> (PromptParts, String?) {
        var parts = PromptParts(question: question)
        guard !contextItems.isEmpty else { return (parts, nil) }
        if !question.isEmpty {
            parts.answerLanguage = SystemInstructions.answerLanguage(for: question, preference: preferences.responseLanguage)
        }
        for item in contextItems {
            switch item {
            case .selection(let selection):
                parts.selection = selection.text
                parts.app = selection.app?.name
                activeSelection = selection
            case .clipboard(let text):
                parts.clipboard = text
            case .window(let capture):
                parts.window = capture
            }
        }
        let summary = contextItems.map(\.summary).joined(separator: " · ")
        contextItems = []
        return (parts, summary)
    }

    static func summary(_ item: ContextItem) -> String { item.summary }

    /// "Go deeper": a follow-up in the same session.
    func goDeeper() {
        guard canFollowUp else { return }
        touch()
        ask(Request(displayedQuestion: String(localized: "Go deeper"), route: conversation?.route ?? .onDevice,
                    isGoDeeper: true, parts: PromptParts(question: SystemInstructions.goDeeper), fitsContext: false))
    }

    /// "Think harder": repeat the last question on Private Cloud Compute with deep reasoning,
    /// with its full, untruncated context (the cloud model's window is larger).
    func thinkHarder() {
        guard let turn = turns.last(where: { $0.kind == .model && !$0.isGoDeeper }) else { return }
        touch()
        let parts = partsByTurn[turn.id] ?? PromptParts(question: turn.question)
        ask(Request(displayedQuestion: turn.question, route: .privateCloud, reasoning: .deep, explicitRoute: true,
                    contextSummary: turn.contextSummary, parts: parts))
    }

    func cancel() {
        generationTask?.cancel()
        generationTask = nil
    }

    func copyCurrentAnswer() {
        guard let answer = currentTurn?.answer, !answer.isEmpty else { return }
        pasteboard.setString(answer)
        showFlash(String(localized: "Copied"))
        if preferences.closePanelAfterCopy { onRequestClose?() }
    }

    // MARK: Private

    private func touch() {
        if clock() - lastActivity > Self.sessionTimeout {
            turns = []
            conversation = nil
            activeSelection = nil
        }
        lastActivity = clock()
    }

    private func ensureConversation(route: ModelRoute = .onDevice) -> (any ModelConversation)? {
        if let conversation, conversation.route == route { return conversation }
        do {
            let instructions = SystemInstructions.general(language: preferences.responseLanguage)
            let created = try model.makeConversation(route: route, instructions: instructions)
            conversation = created
            return created
        } catch {
            return nil
        }
    }

    private struct Request {
        var displayedQuestion: String
        var route: ModelRoute
        var reasoning: ReasoningEffort?
        var explicitRoute = false
        var isGoDeeper = false
        var contextSummary: String?
        var parts: PromptParts
        /// Already cut by `ActionRunner`.
        var wasTruncated = false
        /// Fit the selection/clipboard into the window before sending.
        var fitsContext = true
    }

    private func ask(_ request: Request) {
        let route: ModelRoute
        do {
            route = try preferences.routingPolicy.resolve(request.route, explicit: request.explicitRoute)
        } catch {
            turns.append(ConversationTurn(question: request.displayedQuestion, route: request.route, kind: .model,
                                          state: .failed(ModelError(error).localizedDescription)))
            return
        }

        refreshAvailability()
        if route == .onDevice && !availability.isAvailable {
            turns.append(ConversationTurn(question: request.displayedQuestion, route: route, kind: .model,
                                          state: .failed(availability.message)))
            return
        }

        guard let conversation = ensureConversation(route: route) else {
            turns.append(ConversationTurn(question: request.displayedQuestion, route: route, kind: .model,
                                          state: .failed(ModelError.privateCloudNotInBuild.localizedDescription)))
            return
        }

        // What the session already holds, to leave room for it.
        let history = turns.filter { $0.kind == .model && $0.route == route }
            .map { (sentTextByTurn[$0.id] ?? $0.question) + "\n" + $0.answer }

        var turn = ConversationTurn(question: request.displayedQuestion, route: route, kind: .model, state: .streaming)
        turn.isGoDeeper = request.isGoDeeper
        turn.contextSummary = request.contextSummary
        turn.wasTruncated = request.wasTruncated
        turns.append(turn)
        let turnID = turn.id
        partsByTurn[turnID] = request.parts
        let instructions = SystemInstructions.general(language: preferences.responseLanguage)

        generationTask = Task { [weak self, budget] in
            var prompt = request.parts.full
            if request.fitsContext && request.parts.hasText {
                let parts = request.parts
                let scaffold = parts.compose(selection: parts.selection.map { _ in "" },
                                             clipboard: parts.clipboard.map { _ in "" }).text
                let fitted = await budget.fit([parts.selection, parts.clipboard], route: route,
                                              fixed: [instructions, scaffold] + history,
                                              images: parts.window == nil ? 0 : 1)
                prompt = parts.compose(selection: fitted.texts[0], clipboard: fitted.texts[1])
                if fitted.wasTruncated { self?.update(turnID) { $0.wasTruncated = true } }
            }
            if Task.isCancelled {
                self?.update(turnID) { $0.state = .cancelled }
                return
            }
            self?.sentTextByTurn[turnID] = prompt.text

            do {
                for try await text in conversation.stream(prompt, reasoning: request.reasoning) {
                    self?.update(turnID) { $0.answer = text }
                }
                if Task.isCancelled {
                    self?.update(turnID) { $0.state = .cancelled }
                } else {
                    self?.update(turnID) { $0.state = .done }
                    self?.announceCompletion(turnID)
                }
            } catch is CancellationError {
                self?.update(turnID) { $0.state = .cancelled }
            } catch {
                let message = (error as? LocalizedError)?.errorDescription
                    ?? ModelError.other.localizedDescription
                self?.update(turnID) { $0.state = .failed(message) }
            }
            if let self { self.lastActivity = self.clock() }
        }
    }

    private func update(_ id: UUID, _ change: (inout ConversationTurn) -> Void) {
        guard let index = turns.firstIndex(where: { $0.id == id }) else { return }
        change(&turns[index])
    }

    private func announceCompletion(_ id: UUID) {
        guard let turn = turns.first(where: { $0.id == id }), !turn.answer.isEmpty else { return }
        AccessibilityNotification.Announcement(turn.answer).post()
    }

    private func showFlash(_ text: String) {
        flash = text
        flashTask?.cancel()
        flashTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            self?.flash = nil
        }
    }
}
