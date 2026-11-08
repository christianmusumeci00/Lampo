import AppIntents
import Foundation

// Shortcuts integration. The logic lives in `ShortcutsService` (tested); these types only describe
// the intents to the system. The service is registered with `AppDependencyManager` at launch.

/// A Lampo action, as Shortcuts shows it.
struct LampoActionEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Lampo Action"
    static let defaultQuery = LampoActionQuery()

    let id: UUID
    let name: String
    let symbol: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", image: .init(systemName: symbol))
    }

    init(_ action: LampoAction) {
        id = action.id
        name = action.name
        symbol = action.symbol
    }
}

struct LampoActionQuery: EntityQuery {
    @Dependency private var service: ShortcutsService

    func entities(for identifiers: [LampoActionEntity.ID]) async throws -> [LampoActionEntity] {
        let service = self.service
        return await MainActor.run {
            service.actions.filter { identifiers.contains($0.id) }.map(LampoActionEntity.init)
        }
    }

    func suggestedEntities() async throws -> [LampoActionEntity] {
        let service = self.service
        return await MainActor.run {
            service.actions.filter { $0.input != .screen }.map(LampoActionEntity.init)
        }
    }
}

/// "Ask Lampo": answers a question with the model on this Mac.
struct AskLampoIntent: AppIntent {
    static let title: LocalizedStringResource = "Ask Lampo"
    static let description = IntentDescription("Answers a question with Apple's model on this Mac. Nothing leaves your Mac.")
    static let supportedModes: IntentModes = .background

    @Parameter(title: "Question", inputOptions: String.IntentInputOptions(multiline: true))
    var question: String

    @Dependency private var service: ShortcutsService

    static var parameterSummary: some ParameterSummary {
        Summary("Ask Lampo \(\.$question)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let answer = try await service.ask(question)
        return .result(value: answer.text, dialog: "\(answer.text)")
    }
}

/// "Run Lampo Action": runs one of the user's actions on a text and returns the result.
struct RunLampoActionIntent: AppIntent {
    static let title: LocalizedStringResource = "Run Lampo Action"
    static let description = IntentDescription(
        "Runs a Lampo action (Correct, More formal, Translate, …) on a text and returns the result. Create event and Create reminder open a card to confirm.")
    static let supportedModes: IntentModes = .background

    @Parameter(title: "Action")
    var action: LampoActionEntity

    @Parameter(title: "Text", inputOptions: String.IntentInputOptions(multiline: true))
    var text: String?

    @Dependency private var service: ShortcutsService

    static var parameterSummary: some ParameterSummary {
        Summary("Run \(\.$action) on \(\.$text)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        if let answer = try await service.run(actionID: action.id, on: text ?? "") {
            return .result(value: answer.text, dialog: "\(answer.text)")
        }
        return .result(value: "", dialog: "Check the details in Lampo and confirm.")
    }
}

struct LampoShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AskLampoIntent(),
                    phrases: ["Ask \(.applicationName)", "Ask a question with \(.applicationName)"],
                    shortTitle: "Ask Lampo", systemImageName: "bolt.fill")
        AppShortcut(intent: RunLampoActionIntent(),
                    phrases: ["Run a \(.applicationName) action"],
                    shortTitle: "Run Lampo Action", systemImageName: "sparkles")
    }

    static let shortcutTileColor: ShortcutTileColor = .blue
}
