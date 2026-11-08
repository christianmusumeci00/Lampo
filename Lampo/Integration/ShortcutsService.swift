import Foundation

enum ShortcutsError: LocalizedError, Equatable {
    case actionNotFound
    case needsScreen
    case emptyText
    case disabled

    var errorDescription: String? {
        switch self {
        case .actionNotFound: return String(localized: "That Lampo action no longer exists.")
        case .needsScreen: return String(localized: "This action looks at the screen: run it with its keyboard shortcut.")
        case .emptyText: return String(localized: "There's no text to work on.")
        case .disabled: return String(localized: "Lampo is disabled. Turn it on from the menu bar.")
        }
    }
}

/// What the Shortcuts app (App Intents) can ask Lampo. UI-free and tested with mocks;
/// the intents in `LampoIntents.swift` are thin wrappers.
@MainActor
final class ShortcutsService {
    struct Answer: Equatable, Sendable {
        var text: String
        var route: ModelRoute
    }

    private let model: any ModelService
    private let preferences: Preferences
    private let actionStore: ActionStore
    private let history: HistoryStore?
    /// Opens the confirmation card for "Create event"/"Create reminder" (it needs the user).
    var showDraft: ((DraftKind, String) -> Void)?
    /// Opens the Extract card for a text.
    var showExtraction: ((String) -> Void)?

    init(model: any ModelService, preferences: Preferences, actionStore: ActionStore, history: HistoryStore? = nil) {
        self.model = model
        self.preferences = preferences
        self.actionStore = actionStore
        self.history = history
    }

    /// Turned-on actions only.
    var actions: [LampoAction] { actionStore.enabledActions }

    /// "Ask Lampo": one question, answered on this Mac in a fresh session.
    func ask(_ question: String) async throws -> Answer {
        guard preferences.isEnabled else { throw ShortcutsError.disabled }
        let question = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { throw ShortcutsError.emptyText }
        if case .success(let value)? = Calculator.evaluate(question) {
            return Answer(text: Calculator.format(value), route: .onDevice)
        }
        let availability = model.availability()
        guard availability.isAvailable else { throw ModelError.unavailable(availability) }
        let conversation = try model.makeConversation(
            route: .onDevice, instructions: SystemInstructions.general(language: preferences.responseLanguage))
        var answer = ""
        for try await text in conversation.stream(ModelPrompt(question), reasoning: nil) { answer = text }
        let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ModelError.emptyResponse }
        history?.record(source: String(localized: "Shortcuts app", comment: "The Shortcuts app (Comandi rapidi), as a history source"), input: question, output: trimmed, route: .onDevice)
        return Answer(text: trimmed, route: .onDevice)
    }

    /// "Run Lampo action" on a text. Returns the result; "Create event/reminder" opens the card
    /// instead and returns nil, since nothing is written without the user's confirmation.
    func run(actionID: UUID, on text: String) async throws -> Answer? {
        guard preferences.isEnabled else { throw ShortcutsError.disabled }
        guard let action = actionStore.action(id: actionID), action.isEnabled else { throw ShortcutsError.actionNotFound }
        if action.input == .screen { throw ShortcutsError.needsScreen }
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if action.input != .none && input.isEmpty { throw ShortcutsError.emptyText }

        if let kind = action.output.draftKind {
            showDraft?(kind, input)
            return nil
        }
        if action.output == .extract {
            showExtraction?(input)
            return nil
        }
        let runner = ActionRunner(model: model, preferences: preferences)
        var context = runner.templateContext(selection: action.input == .selection || action.isTranslation ? input : nil,
                                             clipboard: action.input == .clipboard ? input : nil, app: nil)
        // A dictation action run from Shortcuts cleans up the text it's given (e.g. a transcript).
        if action.isDictation { context.dictation = input }
        let run = try await runner.start(action, context: context)
        var output = ""
        for try await chunk in run.stream { output = chunk }
        let cleaned = action.isTranslation ? output
            : action.input == .selection ? RewriteCleaner.clean(output, original: input)
            : output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { throw ModelError.emptyResponse }
        history?.record(source: action.name, input: input, output: cleaned, route: run.route)
        return Answer(text: cleaned, route: run.route)
    }
}
