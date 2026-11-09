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

    /// Text read from the attached window.
    var screenText: String? { window?.text }

    var hasText: Bool { selection != nil || clipboard != nil || screenText != nil }

    /// The untruncated prompt.
    var full: ModelPrompt { compose(selection: selection, clipboard: clipboard, screenText: screenText) }

    /// The prompt with the given (possibly cut) context texts.
    func compose(selection: String?, clipboard: String?, screenText: String?) -> ModelPrompt {
        let block = SystemInstructions.contextBlock(
            selection: selection, app: app, clipboard: clipboard,
            window: window.map { (app: $0.app.name, title: $0.title) }, screenText: screenText,
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

/// One event or reminder of a confirmation card.
struct DraftItem: Identifiable, Equatable {
    let id = UUID()
    var event: CalendarEventDraft
    var reminder: ReminderDraft
    /// Unticked items of a list aren't added.
    var isIncluded = true

    func title(for kind: DraftKind) -> String { kind == .event ? event.title : reminder.title }
}

/// The "Create event" / "Create reminder" confirmation card: one item, or a list of them
/// ("latte, chiamare Luca domani, bolletta venerdì").
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
    /// Never empty.
    var items: [DraftItem]
    var phase: Phase
    /// The failure is a denied permission: offer System Settings.
    var needsSettings = false
    /// Items added so far. After a partial failure the added ones leave the list, so a retry
    /// doesn't add them twice.
    var savedCount = 0

    init(kind: DraftKind, event: CalendarEventDraft, reminder: ReminderDraft, phase: Phase) {
        self.init(kind: kind, items: [DraftItem(event: event, reminder: reminder)], phase: phase)
    }

    init(kind: DraftKind, items: [DraftItem], phase: Phase) {
        self.kind = kind
        self.items = items
        self.phase = phase
    }

    var isList: Bool { items.count > 1 }
    var included: [DraftItem] { items.filter(\.isIncluded) }

    /// The first item (the only one, unless it's a list).
    var event: CalendarEventDraft {
        get { items[0].event }
        set { items[0].event = newValue }
    }

    var reminder: ReminderDraft {
        get { items[0].reminder }
        set { items[0].reminder = newValue }
    }

    var canConfirm: Bool {
        switch phase {
        case .editing, .failed:
            return !included.isEmpty
                && included.allSatisfy { !$0.title(for: kind).trimmingCharacters(in: .whitespaces).isEmpty }
        default: return false
        }
    }

    var title: String { items[0].title(for: kind) }
}

/// "Extract": a contact, a table or to-dos pulled out of a text. To-dos continue in the
/// draft card (a list of reminders).
struct ExtractionCard: Equatable {
    enum Phase: Equatable {
        case reading
        case ready
        case failed(String)
    }

    var kind: ExtractKind
    var source: String
    var contact = ContactDraft()
    var table = ExtractedTable()
    var phase: Phase = .reading
    /// The model couldn't help: the result comes from simple rules (phone numbers, separators).
    var isFallback = false
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
    /// "Extract" card, shown instead of the conversation.
    var extraction: ExtractionCard?
    /// "Reply": the language of the message being answered. Follow-ups rewrite the reply in it.
    private(set) var replyLanguage: String?
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
    /// Saves a contact by handing it to Contacts, which asks before adding. Returns false on failure.
    @ObservationIgnored var openContact: (ContactDraft) -> Bool = { ContactExporter.open($0) }
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
    var hasContent: Bool { !turns.isEmpty || draft != nil || extraction != nil }
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
        onInsert?(MarkdownText.plain(answer), activeSelection)
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
        extraction = nil
        replyLanguage = nil
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
        if draft != nil || extraction != nil {
            draftTask?.cancel()
            draft = nil
            extraction = nil
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

        if let replyLanguage, contextItems.isEmpty, canFollowUp {
            // "più breve", "say yes to Thursday": the reply is rewritten, in the message's language.
            let instruction = """
                Change the reply as the user asks: “\(text)”. Write the whole reply again in \(replyLanguage), \
                ready to send, without a name or signature at the end, and return only the reply.
                """
            ask(Request(displayedQuestion: text, route: conversation?.route ?? .onDevice,
                        parts: PromptParts(question: instruction), fitsContext: false))
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
        if BuiltInActions.insertsAtCursor.contains(action.id) {
            // A reply goes where the cursor is, never over the selected message.
            activeSelection = nil
            replyLanguage = parts.selection.flatMap { TextLanguage.name(of: $0) }
                ?? SystemInstructions.languageName(preferences.responseLanguage)
        }
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
            // Actions arrive with their selection already fitted; the window's text never is.
            if (request.fitsContext && request.parts.hasText) || request.parts.screenText != nil {
                var parts = request.parts
                if !request.fitsContext {
                    parts.selection = nil
                    parts.clipboard = nil
                }
                let scaffold = parts.compose(selection: parts.selection.map { _ in "" },
                                             clipboard: parts.clipboard.map { _ in "" },
                                             screenText: parts.screenText.map { _ in "" }).text
                let fitted = await budget.fit([parts.selection, parts.clipboard, parts.screenText], route: route,
                                              fixed: [instructions, scaffold] + history,
                                              images: parts.window == nil ? 0 : 1)
                prompt = parts.compose(selection: fitted.texts[0], clipboard: fitted.texts[1], screenText: fitted.texts[2])
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
    /// the draft is built from the date parser alone and is still editable. A short list
    /// becomes one item each, dated by the parser alone (one model call in all).
    func startDraft(_ kind: DraftKind, from text: String) {
        resetConversation()
        let parser = WhenParser(now: now(), calendar: userCalendar)
        draft = Self.placeholderCard(kind, parser: parser)
        draftTask = Task { [weak self, model] in
            var items = [text]
            if ListSplitter.mayBeList(text) {
                do {
                    items = ListSplitter.reconcile(source: text, items: try await model.splitItems(text))
                } catch is CancellationError {
                    return
                } catch {
                    items = ListSplitter.fallback(text)
                }
            }
            if items.count > 1 {
                guard !Task.isCancelled, let self, self.draft?.phase == .reading else { return }
                self.fillDraft(with: items, parser: parser)
                return
            }

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

    /// One item per entry, titled with its own words minus the day and time.
    private func fillDraft(with entries: [String], parser: WhenParser) {
        draft?.items = entries.map { entry in
            let details = ExtractedDetails(title: DraftBuilder.withoutWhen(entry))
            return DraftItem(event: DraftBuilder.event(from: entry, details: details, parser: parser),
                             reminder: DraftBuilder.reminder(from: entry, details: details, parser: parser))
        }
        draft?.phase = .editing
    }

    private static func placeholderCard(_ kind: DraftKind, parser: WhenParser) -> DraftCard {
        let start = parser.calendar.startOfDay(for: parser.now)
        return DraftCard(
            kind: kind,
            event: CalendarEventDraft(title: "", start: start, end: start, isAllDay: true, location: "", notes: ""),
            reminder: ReminderDraft(title: "", hasDueDate: false, due: start, hasDueTime: false, notes: ""),
            phase: .reading)
    }

    /// No selected text: the panel asks for a description ("cena con Marco giovedì alle 20").
    func enterDraftInput(_ kind: DraftKind) {
        resetConversation()
        draftInputKind = kind
    }

    func cancelDraftInput() {
        draftInputKind = nil
    }

    /// Writes the confirmed draft (every ticked item). Asks for Calendar/Reminders access the first time.
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
            var saved: Set<UUID> = []
            do {
                for item in card.included {
                    switch card.kind {
                    case .event: try writer.save(item.event)
                    case .reminder: try writer.save(item.reminder)
                    }
                    saved.insert(item.id)
                }
                self.draft?.savedCount += saved.count
                self.draft?.phase = .saved
                AccessibilityNotification.Announcement(Self.savedMessage(card.kind, count: self.draft?.savedCount ?? 1)).post()
            } catch {
                if !saved.isEmpty, (self.draft?.items.count ?? 0) > saved.count {
                    self.draft?.items.removeAll { saved.contains($0.id) }
                    self.draft?.savedCount += saved.count
                }
                self.draft?.phase = .failed((error as? LocalizedError)?.errorDescription ?? CalendarWriteError.saveFailed.localizedDescription)
            }
        }
    }

    static func savedMessage(_ kind: DraftKind, count: Int) -> String {
        if count > 1 {
            return kind == .event ? String(localized: "Added \(count) events to Calendar")
                : String(localized: "Added \(count) reminders to Reminders")
        }
        return kind == .event ? String(localized: "Added to Calendar") : String(localized: "Added to Reminders")
    }

    // MARK: Extract

    /// "Extract" on a text: guesses the kind from its shape; the user can switch.
    func startExtraction(from text: String, kind: ExtractKind? = nil) {
        resetConversation()
        extraction = ExtractionCard(kind: kind ?? ExtractKind.guess(for: text), source: text)
        runExtraction()
    }

    func switchExtraction(to kind: ExtractKind) {
        guard let card = extraction, card.kind != kind else { return }
        draftTask?.cancel()
        draft = nil
        extraction = ExtractionCard(kind: kind, source: card.source)
        runExtraction()
    }

    private func runExtraction() {
        guard let card = extraction else { return }
        let text = card.source
        let parser = WhenParser(now: now(), calendar: userCalendar)
        draftTask = Task { [weak self, model] in
            var updated = card
            do {
                switch card.kind {
                case .contact:
                    updated.contact = try await model.extractContact(from: text).checked(against: text)
                case .table:
                    updated.table = try await model.extractTable(from: text).normalized()
                case .todos:
                    let tasks = try await model.extractTasks(from: text)
                    guard !Task.isCancelled, let self, self.extraction?.kind == .todos else { return }
                    self.showTasks(tasks, parser: parser)
                    return
                }
            } catch is CancellationError {
                return
            } catch {
                Log.model.info("extraction failed; using simple rules")
                updated.isFallback = true
                switch card.kind {
                case .contact: updated.contact = ContactDraft.detected(in: text)
                case .table: updated.table = TableShape.parse(text)
                case .todos:
                    guard !Task.isCancelled, let self, self.extraction?.kind == .todos else { return }
                    self.extraction?.isFallback = true
                    self.showTasks(ListSplitter.segments(of: text, splittingCommas: false), parser: parser)
                    return
                }
            }
            guard !Task.isCancelled, let self, self.extraction?.kind == card.kind,
                  self.extraction?.phase == .reading else { return }
            let isEmpty = card.kind == .contact ? updated.contact.isEmpty : updated.table.isEmpty
            updated.phase = isEmpty ? .failed(Self.nothingFound(card.kind)) : .ready
            self.extraction = updated
        }
    }

    /// To-dos continue as a list of reminders in the draft card.
    private func showTasks(_ tasks: [String], parser: WhenParser) {
        var seen: Set<String> = []
        let entries = tasks.map(ListSplitter.cleanItem).filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
        guard !entries.isEmpty else {
            extraction?.phase = .failed(Self.nothingFound(.todos))
            return
        }
        extraction?.phase = .ready
        draft = Self.placeholderCard(.reminder, parser: parser)
        fillDraft(with: Array(entries.prefix(ListSplitter.maximumItems)), parser: parser)
    }

    static func nothingFound(_ kind: ExtractKind) -> String {
        switch kind {
        case .contact: return String(localized: "No contact details in this text.")
        case .table: return String(localized: "No table in this text.")
        case .todos: return String(localized: "No to-dos in this text.")
        }
    }

    /// Opens the contact in Contacts, which asks before adding it.
    func saveContact() {
        guard let contact = extraction?.contact, extraction?.phase == .ready, !contact.isEmpty else { return }
        if openContact(contact) {
            onRequestClose?()
        } else {
            extraction?.phase = .failed(String(localized: "Couldn't open Contacts. Try again."))
        }
    }

    func copyContact() {
        guard let contact = extraction?.contact, !contact.isEmpty else { return }
        pasteboard.setString(contact.plainText)
        showFlash(String(localized: "Copied"))
    }

    /// Tab-separated (pastes as cells in Numbers and Excel), or Markdown.
    func copyTable(asMarkdown: Bool = false) {
        guard let table = extraction?.table, !table.isEmpty else { return }
        pasteboard.setString(asMarkdown ? table.markdown : table.tabSeparated)
        showFlash(String(localized: "Copied"))
        if preferences.closePanelAfterCopy { onRequestClose?() }
    }

    func discardDraft() {
        draftTask?.cancel()
        draft = nil
        extraction = nil
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
