import Foundation

/// Turns an action plus context into a model stream.
@MainActor
final class ActionRunner {
    struct Run {
        var route: ModelRoute
        var prompt: String
        var stream: AsyncThrowingStream<String, Error>
    }

    private let model: any ModelService
    private let preferences: Preferences

    init(model: any ModelService, preferences: Preferences) {
        self.model = model
        self.preferences = preferences
    }

    func templateContext(selection: String?, clipboard: String?, app: String?) -> TemplateContext {
        TemplateContext(selection: selection, clipboard: clipboard, app: app,
                        language: SystemInstructions.languageName(preferences.responseLanguage))
    }

    func prompt(for action: LampoAction, context: TemplateContext) -> String {
        PromptTemplate.render(action.promptTemplate, context: context, input: action.input)
    }

    /// Each run is a fresh, single-turn session: actions don't share history.
    func start(_ action: LampoAction, context: TemplateContext) throws -> Run {
        let route: ModelRoute
        do {
            route = try preferences.routingPolicy.resolve(action.route, explicit: false)
        } catch {
            throw ModelError(error)
        }
        let availability = model.availability()
        if route == .onDevice && !availability.isAvailable {
            throw ModelError.unavailable(availability)
        }
        let prompt = prompt(for: action, context: context)
        let conversation = try model.makeConversation(
            route: route, instructions: SystemInstructions.action(language: preferences.responseLanguage))
        let reasoning: ReasoningEffort? = route == .privateCloud ? .light : nil
        return Run(route: route, prompt: prompt, stream: conversation.stream(ModelPrompt(prompt), reasoning: reasoning))
    }
}
