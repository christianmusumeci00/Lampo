import Foundation

/// A reusable instruction bound to a global shortcut.
/// The shortcut itself lives in KeyboardShortcuts, under `shortcutName` (derived from `id`).
struct LampoAction: Codable, Identifiable, Hashable, Sendable {
    enum InputSource: String, Codable, CaseIterable, Sendable {
        case selection
        case clipboard
        case screen
        case none
    }

    enum OutputMode: String, Codable, CaseIterable, Sendable {
        /// Show the Lens with a preview; the user replaces, copies or retries.
        case preview
        /// Run and replace the selection immediately, with only a small HUD.
        case replaceSilently
        /// Run and copy the result.
        case copy
        /// Open the Glass panel with the result, for follow-ups.
        case openPanel
        /// Turn the text into a calendar event, confirmed in an editable card.
        case calendarEvent
        /// Turn the text into a reminder, confirmed in an editable card.
        case reminder

        /// Structured outputs don't use the prompt template.
        var draftKind: DraftKind? {
            switch self {
            case .calendarEvent: return .event
            case .reminder: return .reminder
            default: return nil
            }
        }

        /// Actions offered as Lens chips: the ones that rewrite text.
        var showsInLens: Bool { self == .preview || self == .replaceSilently || self == .copy }
    }

    var id: UUID
    var name: String
    var symbol: String
    /// Supports {{selection}}, {{clipboard}}, {{app}}, {{language}}.
    var promptTemplate: String
    var input: InputSource
    var output: OutputMode
    var route: ModelRoute
    var isBuiltIn: Bool

    init(id: UUID = UUID(), name: String, symbol: String, promptTemplate: String,
         input: InputSource = .selection, output: OutputMode = .preview,
         route: ModelRoute = .onDevice, isBuiltIn: Bool = false) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.promptTemplate = promptTemplate
        self.input = input
        self.output = output
        self.route = route
        self.isBuiltIn = isBuiltIn
    }
}
