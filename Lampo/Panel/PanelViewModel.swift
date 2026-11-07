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

    var isFinished: Bool { state != .streaming }
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

    @ObservationIgnored private let model: any ModelService
    @ObservationIgnored private let preferences: Preferences
    @ObservationIgnored private let pasteboard: any PasteboardClient
    @ObservationIgnored private let clock: () -> ContinuousClock.Instant
    @ObservationIgnored private var conversation: (any ModelConversation)?
    @ObservationIgnored private(set) var generationTask: Task<Void, Never>?
    @ObservationIgnored private var lastActivity: ContinuousClock.Instant
    @ObservationIgnored private var flashTask: Task<Void, Never>?

    /// The selection the current conversation is about; "Insert" replaces it.
    @ObservationIgnored private(set) var activeSelection: SelectionContext?

    /// Called after a successful copy when "close after copy" is on.
    @ObservationIgnored var onRequestClose: (() -> Void)?
    /// Called by "Insert ⌘↩" with the answer and the selection to replace (if any).
    @ObservationIgnored var onInsert: ((String, SelectionContext?) -> Void)?

    init(
        model: any ModelService,
        preferences: Preferences,
        pasteboard: any PasteboardClient,
        clock: @escaping () -> ContinuousClock.Instant = { .now }
    ) {
        self.model = model
        self.preferences = preferences
        self.pasteboard = pasteboard
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

    // MARK: Lifecycle

    /// Called every time the panel is shown.
    func panelWillAppear() {
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
        query = ""
        focusRequest += 1
    }

    // MARK: Actions

    func submit() {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isGenerating else { return }
        query = ""
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

        let (prompt, summary) = consumeContext(question: text)
        ask(ModelPrompt(prompt), displayedQuestion: text, route: .onDevice, reasoning: nil, explicitRoute: false,
            contextSummary: summary)
    }

    /// Runs an action whose result belongs in the panel (e.g. "Explain").
    func runAction(_ action: LampoAction, prompt: String, contextItems items: [ContextItem]) {
        resetConversation()
        contextItems = items
        _ = consumeContext(question: "")
        touch()
        ask(ModelPrompt(prompt), displayedQuestion: action.name, route: action.route, reasoning: nil,
            explicitRoute: false, contextSummary: items.first.map(Self.summary))
    }

    /// Builds the prompt from the chips (then clears them: the session now has the context).
    private func consumeContext(question: String) -> (String, String?) {
        guard !contextItems.isEmpty else { return (question, nil) }
        var selectionText: String?
        var app: String?
        var clipboard: String?
        for item in contextItems {
            switch item {
            case .selection(let selection):
                selectionText = selection.text
                app = selection.app?.name
                activeSelection = selection
            case .clipboard(let text):
                clipboard = text
            }
        }
        let summary = contextItems.map(Self.summary).joined(separator: " · ")
        contextItems = []
        let block = SystemInstructions.contextBlock(selection: selectionText, app: app, clipboard: clipboard)
        return (question.isEmpty ? block : block + "\n\n" + question, summary)
    }

    static func summary(_ item: ContextItem) -> String {
        switch item {
        case .selection(let selection):
            return String(localized: "Selection · \(selection.wordCount) words")
        case .clipboard:
            return String(localized: "Clipboard")
        }
    }

    /// "Go deeper": a follow-up in the same session.
    func goDeeper() {
        guard canFollowUp else { return }
        touch()
        ask(ModelPrompt(SystemInstructions.goDeeper),
            displayedQuestion: String(localized: "Go deeper"),
            route: conversation?.route ?? .onDevice, reasoning: nil, explicitRoute: false,
            isGoDeeper: true)
    }

    /// "Think harder": repeat the last question on Private Cloud Compute with deep reasoning.
    func thinkHarder() {
        guard let question = turns.last(where: { $0.kind == .model && !$0.isGoDeeper })?.question else { return }
        touch()
        ask(ModelPrompt(question), displayedQuestion: question, route: .privateCloud, reasoning: .deep, explicitRoute: true)
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

    private func ask(_ prompt: ModelPrompt, displayedQuestion: String, route requested: ModelRoute,
                     reasoning: ReasoningEffort?, explicitRoute: Bool, isGoDeeper: Bool = false,
                     contextSummary: String? = nil) {
        let route: ModelRoute
        do {
            route = try preferences.routingPolicy.resolve(requested, explicit: explicitRoute)
        } catch {
            turns.append(ConversationTurn(question: displayedQuestion, route: requested, kind: .model,
                                          state: .failed(ModelError(error).localizedDescription)))
            return
        }

        refreshAvailability()
        if route == .onDevice && !availability.isAvailable {
            turns.append(ConversationTurn(question: displayedQuestion, route: route, kind: .model,
                                          state: .failed(availability.message)))
            return
        }

        guard let conversation = ensureConversation(route: route) else {
            turns.append(ConversationTurn(question: displayedQuestion, route: route, kind: .model,
                                          state: .failed(ModelError.privateCloudNotInBuild.localizedDescription)))
            return
        }

        var turn = ConversationTurn(question: displayedQuestion, route: route, kind: .model, state: .streaming)
        turn.isGoDeeper = isGoDeeper
        turn.contextSummary = contextSummary
        turns.append(turn)
        let turnID = turns[turns.count - 1].id
        let stream = conversation.stream(prompt, reasoning: reasoning)

        generationTask = Task { [weak self] in
            do {
                for try await text in stream {
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
