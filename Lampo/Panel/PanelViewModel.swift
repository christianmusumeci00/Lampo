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

/// The "Create event" / "Create reminder" confirmation card.
struct DraftCard: Equatable {
    enum Phase: Equatable {
        /// The model is reading the text.
        case reading
        case editing
        case saving
        case saved
        case failed(String)
    }

    var kind: DraftKind
    var event: CalendarEventDraft
    var reminder: ReminderDraft
    var phase: Phase
    /// The failure is a denied permission: offer System Settings.
    var needsSettings = false

    var canConfirm: Bool {
        switch phase {
        case .editing, .failed: return !title.trimmingCharacters(in: .whitespaces).isEmpty
        default: return false
        }
    }

    var title: String { kind == .event ? event.title : reminder.title }
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
    /// "Create event"/"Create reminder" card, shown instead of the conversation.
    var draft: DraftCard?
    /// The panel is waiting for the user to describe an event or reminder.
    private(set) var draftInputKind: DraftKind?
    /// A system permission prompt is up: the panel must not close when it loses focus.
    private(set) var isWaitingForSystemPrompt = false

    @ObservationIgnored private let model: any ModelService
    @ObservationIgnored private let preferences: Preferences
    @ObservationIgnored private let pasteboard: any PasteboardClient
    @ObservationIgnored private let screenCapture: any ScreenCapturing
    @ObservationIgnored private let budget: ContextBudget
    @ObservationIgnored let calendarWriter: any CalendarWriting
    @ObservationIgnored let now: () -> Date
    /// Calendar (and time zone) used to resolve "giovedì", "domani"…
    @ObservationIgnored var userCalendar: Calendar = .current
    @ObservationIgnored var draftTask: Task<Void, Never>?
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
    /// Called when a system prompt closes, so the panel can take focus back.
    @ObservationIgnored var onSystemPromptFinished: (() -> Void)?
    /// Called with each completed model answer (for the optional local history).
    @ObservationIgnored var onTurnCompleted: ((ConversationTurn) -> Void)?

    init(
        model: any ModelService,
        preferences: Preferences,
        pasteboard: any PasteboardClient,
        screenCapture: any ScreenCapturing = ScreenCaptureService(),
        calendarWriter: (any CalendarWriting)? = nil,
        now: @escaping () -> Date = { .now },
        clock: @escaping () -> ContinuousClock.Instant = { .now }
    ) {
        self.calendarWriter = calendarWriter ?? CalendarService()
        self.now = now
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
    var hasContent: Bool { !turns.isEmpty || draft != nil }
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
        draftTask?.cancel()
        draftTask = nil
        draft = nil
        draftInputKind = nil
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
        if let kind = draftInputKind {
            startDraft(kind, from: text)
            return
        }
        if draft != nil {
            draftTask?.cancel()
            draft = nil
        }
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
                    if let self, let turn = self.turns.first(where: { $0.id == turnID }) {
                        self.onTurnCompleted?(turn)
                    }
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

    // MARK: Drafts (Create event / Create reminder)

    /// Reads `text` into an editable draft. If the model can't help (unavailable, refused),
    /// the draft is built from the date parser alone and is still editable.
    func startDraft(_ kind: DraftKind, from text: String) {
        resetConversation()
        let parser = WhenParser(now: now(), calendar: userCalendar)
        let start = parser.calendar.startOfDay(for: parser.now)
        draft = DraftCard(
            kind: kind,
            event: CalendarEventDraft(title: "", start: start, end: start, isAllDay: true, location: "", notes: ""),
            reminder: ReminderDraft(title: "", hasDueDate: false, due: start, hasDueTime: false, notes: ""),
            phase: .reading)
        draftTask = Task { [weak self, model] in
            var details = ExtractedDetails()
            do {
                details = try await model.extractDetails(from: text, kind: kind)
            } catch is CancellationError {
                return
            } catch {
                Log.model.info("extraction failed; using the date parser only")
            }
            guard !Task.isCancelled, let self, self.draft?.phase == .reading else { return }
            self.draft?.event = DraftBuilder.event(from: text, details: details, parser: parser)
            self.draft?.reminder = DraftBuilder.reminder(from: text, details: details, parser: parser)
            self.draft?.phase = .editing
        }
    }

    /// No selected text: the panel asks for a description ("cena con Marco giovedì alle 20").
    func enterDraftInput(_ kind: DraftKind) {
        resetConversation()
        draftInputKind = kind
    }

    func cancelDraftInput() {
        draftInputKind = nil
    }

    /// Writes the confirmed draft. Asks for Calendar/Reminders access the first time.
    func confirmDraft() {
        guard let card = draft, card.canConfirm else { return }
        draft?.phase = .saving
        draft?.needsSettings = false
        let writer = calendarWriter
        draftTask = Task { [weak self] in
            var access = writer.access(for: card.kind)
            if access == .notDetermined {
                self?.isWaitingForSystemPrompt = true
                access = await writer.requestAccess(for: card.kind) ? .granted : .denied
                self?.isWaitingForSystemPrompt = false
                self?.onSystemPromptFinished?()
            }
            guard let self, !Task.isCancelled else { return }
            guard access == .granted else {
                self.draft?.phase = .failed(CalendarWriteError.accessDenied(card.kind).localizedDescription)
                self.draft?.needsSettings = true
                return
            }
            do {
                switch card.kind {
                case .event: try writer.save(card.event)
                case .reminder: try writer.save(card.reminder)
                }
                self.draft?.phase = .saved
                let message = card.kind == .event ? String(localized: "Added to Calendar") : String(localized: "Added to Reminders")
                AccessibilityNotification.Announcement(message).post()
            } catch {
                self.draft?.phase = .failed((error as? LocalizedError)?.errorDescription ?? CalendarWriteError.saveFailed.localizedDescription)
            }
        }
    }

    func discardDraft() {
        draftTask?.cancel()
        draft = nil
        onRequestClose?()
    }

    func openDraftSettings() {
        guard let kind = draft?.kind else { return }
        calendarWriter.openSettings(for: kind)
        onRequestClose?()
    }

    func openDraftApp() {
        guard let card = draft else { return }
        calendarWriter.openApp(for: card.kind, at: card.kind == .event ? card.event.start : card.reminder.due)
        onRequestClose?()
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
