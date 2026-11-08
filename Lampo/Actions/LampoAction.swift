import Foundation

/// A reusable instruction bound to a global shortcut.
/// The shortcut itself lives in KeyboardShortcuts, under `shortcutName` (derived from `id`).
struct LampoAction: Codable, Identifiable, Hashable, Sendable {
    enum InputSource: String, Codable, CaseIterable, Sendable {
        case selection
        case clipboard
        case screen
        /// Speech: hold or press the shortcut and talk; the transcript is the input (`{{dictation}}`).
        case dictation
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
        /// Pull a contact, a table or to-dos out of the text, in an editable card.
        case extract

        /// Structured outputs don't use the prompt template.
        var draftKind: DraftKind? {
            switch self {
            case .calendarEvent: return .event
            case .reminder: return .reminder
            default: return nil
            }
        }

        /// Outputs built with guided generation, in a card: they don't use the prompt template.
        var isStructured: Bool { draftKind != nil || self == .extract }

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
    /// Turned-off actions keep their settings but have no hotkey and don't appear in the Lens or menus.
    var isEnabled: Bool
    /// Set for actions that translate with Apple's Translation framework instead of the model:
    /// a language identifier ("en") or `TranslationPlanner.automatic`. The prompt is then unused.
    var translationTarget: String?

    init(id: UUID = UUID(), name: String, symbol: String, promptTemplate: String,
         input: InputSource = .selection, output: OutputMode = .preview,
         route: ModelRoute = .onDevice, isBuiltIn: Bool = false, isEnabled: Bool = true,
         translationTarget: String? = nil) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.promptTemplate = promptTemplate
        self.input = input
        self.output = output
        self.route = route
        self.isBuiltIn = isBuiltIn
        self.isEnabled = isEnabled
        self.translationTarget = translationTarget
    }

    var isTranslation: Bool { translationTarget != nil }

    /// The prompt asks for a tone, chosen in the Lens.
    var usesTone: Bool {
        !isTranslation && promptTemplate.range(of: "\\{\\{\\s*tone\\s*\\}\\}", options: .regularExpression) != nil
    }

    var isDictation: Bool { input == .dictation }

    /// Translations can't continue in the panel: they preview, replace or copy. Dictation has no
    /// selection to preview against, so "preview" inserts at the cursor.
    var effectiveOutput: OutputMode {
        if isTranslation && !output.showsInLens { return .preview }
        if isDictation && output == .preview { return .replaceSilently }
        return output
    }
}

extension LampoAction {
    /// Files from older versions have no `isEnabled` or `translationTarget`.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        symbol = try container.decode(String.self, forKey: .symbol)
        promptTemplate = try container.decode(String.self, forKey: .promptTemplate)
        input = try container.decode(InputSource.self, forKey: .input)
        output = try container.decode(OutputMode.self, forKey: .output)
        route = try container.decode(ModelRoute.self, forKey: .route)
        isBuiltIn = try container.decode(Bool.self, forKey: .isBuiltIn)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        translationTarget = try container.decodeIfPresent(String.self, forKey: .translationTarget)
    }
}

/// How "Rewrite" changes the text. Chosen in the Lens and remembered.
enum RewriteTone: String, CaseIterable, Codable, Sendable {
    case clearer
    case formal
    case friendly
    case shorter

    /// Fills `{{tone}}` in "Rewrite the text … to make it {{tone}}".
    var instruction: String {
        switch self {
        case .clearer: return "clearer and easier to read"
        case .formal: return "more formal and professional"
        case .friendly: return "warmer and more friendly"
        case .shorter: return "about half as long, keeping the key facts"
        }
    }

    var title: String {
        switch self {
        case .clearer: return String(localized: "Clearer")
        case .formal: return String(localized: "Formal")
        case .friendly: return String(localized: "Friendly")
        case .shorter: return String(localized: "Shorter")
        }
    }
}
