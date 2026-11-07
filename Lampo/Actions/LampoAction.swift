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
