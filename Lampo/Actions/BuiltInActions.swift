import AppKit
import Foundation
import KeyboardShortcuts

/// Actions shipped with Lampo. IDs are fixed so shortcuts and user edits survive updates.
/// Prompts are in English (the on-device model follows English instructions best) and
/// ask to keep the text's own language unless translating.
enum BuiltInActions {
    static let correctID = UUID(uuidString: "6C0A0001-0000-4000-8000-00000000C0DE")!
    static let formalID = UUID(uuidString: "6C0A0002-0000-4000-8000-00000000C0DE")!
    static let shorterID = UUID(uuidString: "6C0A0003-0000-4000-8000-00000000C0DE")!
    static let toEnglishID = UUID(uuidString: "6C0A0004-0000-4000-8000-00000000C0DE")!
    static let toItalianID = UUID(uuidString: "6C0A0005-0000-4000-8000-00000000C0DE")!
    static let summarizeID = UUID(uuidString: "6C0A0006-0000-4000-8000-00000000C0DE")!
    static let explainID = UUID(uuidString: "6C0A0007-0000-4000-8000-00000000C0DE")!
    static let askScreenID = UUID(uuidString: "6C0A0008-0000-4000-8000-00000000C0DE")!
    static let createEventID = UUID(uuidString: "6C0A0009-0000-4000-8000-00000000C0DE")!
    static let createReminderID = UUID(uuidString: "6C0A000A-0000-4000-8000-00000000C0DE")!

    static var all: [LampoAction] {
        [
            LampoAction(
                id: correctID, name: String(localized: "Correct"), symbol: "checkmark.circle",
                promptTemplate: """
                Correct spelling, grammar and punctuation in the text below, which is in {{text_language}}. \
                Write the result in {{text_language}}. Keep meaning, tone and formatting. \
                If it is already correct, return it unchanged.

                {{selection}}
                """,
                isBuiltIn: true),
            LampoAction(
                id: formalID, name: String(localized: "More formal"), symbol: "briefcase",
                promptTemplate: """
                Rewrite the text below, which is in {{text_language}}, in a more formal, professional tone. \
                Write the result in {{text_language}}. Keep the meaning.

                {{selection}}
                """,
                isBuiltIn: true),
            LampoAction(
                id: shorterID, name: String(localized: "Shorter"), symbol: "arrow.down.right.and.arrow.up.left",
                promptTemplate: """
                Rewrite the text below, which is in {{text_language}}, to be about half as long. \
                Write the result in {{text_language}}. Keep key facts and tone.

                {{selection}}
                """,
                isBuiltIn: true),
            LampoAction(
                id: toEnglishID, name: String(localized: "Translate to English"), symbol: "character.bubble",
                promptTemplate: """
                Translate the text below into natural English. Keep the formatting.

                {{selection}}
                """,
                isBuiltIn: true),
            LampoAction(
                id: toItalianID, name: String(localized: "Translate to Italian"), symbol: "character.bubble",
                promptTemplate: """
                Translate the text below into natural Italian. Keep the formatting.

                {{selection}}
                """,
                isBuiltIn: true),
            LampoAction(
                id: summarizeID, name: String(localized: "Summarize"), symbol: "text.line.first.and.arrowtriangle.forward",
                promptTemplate: """
                Summarize the text below in a few short bullet points, in {{language}}.

                {{selection}}
                """,
                isBuiltIn: true),
            LampoAction(
                id: explainID, name: String(localized: "Explain"), symbol: "lightbulb",
                promptTemplate: """
                Explain the text below simply and briefly, in {{language}}. It was selected in {{app}}.

                {{selection}}
                """,
                output: .openPanel, isBuiltIn: true),
            // An empty template opens the panel with the window attached and waits for the question.
            LampoAction(
                id: askScreenID, name: String(localized: "Ask the screen"), symbol: "macwindow",
                promptTemplate: "", input: .screen, output: .openPanel, isBuiltIn: true),
            // Structured: the selection (or typed text) becomes an editable draft; nothing is
            // written to Calendar or Reminders without confirmation.
            LampoAction(
                id: createEventID, name: String(localized: "Create event"), symbol: "calendar.badge.plus",
                promptTemplate: "", output: .calendarEvent, isBuiltIn: true),
            LampoAction(
                id: createReminderID, name: String(localized: "Create reminder"), symbol: "checklist",
                promptTemplate: "", output: .reminder, isBuiltIn: true),
        ]
    }

    /// Default global shortcuts (⌥⇧ + letter).
    /// The shortcut name of a built-in action (the user may have changed its shortcut).
    static func shortcutName(for id: UUID) -> KeyboardShortcuts.Name? {
        all.first { $0.id == id }?.shortcutName
    }

    static let defaultShortcuts: [UUID: KeyboardShortcuts.Shortcut] = [
        correctID: .init(.c, modifiers: [.option, .shift]),
        formalID: .init(.f, modifiers: [.option, .shift]),
        shorterID: .init(.b, modifiers: [.option, .shift]),
        toEnglishID: .init(.t, modifiers: [.option, .shift]),
        summarizeID: .init(.r, modifiers: [.option, .shift]),
        askScreenID: .init(.s, modifiers: [.option, .shift]),
        createEventID: .init(.e, modifiers: [.option, .shift]),
        createReminderID: .init(.p, modifiers: [.option, .shift]),
    ]
}

extension LampoAction {
    /// KeyboardShortcuts name for this action. Built-ins get their default shortcut.
    var shortcutName: KeyboardShortcuts.Name {
        KeyboardShortcuts.Name("action-\(id.uuidString)", initial: BuiltInActions.defaultShortcuts[id])
    }
}
