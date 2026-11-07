import CoreGraphics
import Foundation

/// Turns an action plus context into a model stream.
@MainActor
final class ActionRunner {
    /// A prompt ready to send: rendered, routed, and fitted to the context window.
    struct Prepared {
        var route: ModelRoute
        var prompt: String
        /// True when the selection or clipboard was cut to fit ("Long text: used an excerpt").
        var wasTruncated: Bool
    }

    struct Run {
        var route: ModelRoute
        var prompt: String
        var wasTruncated: Bool
        var stream: AsyncThrowingStream<String, Error>
    }

    private let model: any ModelService
    private let preferences: Preferences
    private let budget: ContextBudget

    init(model: any ModelService, preferences: Preferences) {
        self.model = model
        self.preferences = preferences
        self.budget = ContextBudget(model: model)
    }

    var instructions: String { SystemInstructions.action(language: preferences.responseLanguage) }

    func templateContext(selection: String?, clipboard: String?, app: String?) -> TemplateContext {
        TemplateContext(selection: selection, clipboard: clipboard, app: app,
                        language: SystemInstructions.languageName(preferences.responseLanguage))
    }

    func prompt(for action: LampoAction, context: TemplateContext) -> String {
        PromptTemplate.render(action.promptTemplate, context: context, input: action.input)
    }

    /// Resolves the route and fits the context texts into the model's window.
    /// - Parameter routeOverride: "Think harder" runs the action on Private Cloud Compute.
    func prepare(_ action: LampoAction, context: TemplateContext, images: Int = 0,
                 routeOverride: ModelRoute? = nil) async throws -> Prepared {
        let route: ModelRoute
        do {
            route = try preferences.routingPolicy.resolve(routeOverride ?? action.route, explicit: routeOverride != nil)
        } catch {
            throw ModelError(error)
        }
        let availability = model.availability()
        if route == .onDevice && !availability.isAvailable {
            throw ModelError.unavailable(availability)
        }

        // The language is detected on the whole text, before any cut.
        var empty = context
        empty.selection = context.selection.map { _ in "" }
        empty.clipboard = context.clipboard.map { _ in "" }
        let scaffold = prompt(for: action, context: empty)
        let fitted = await budget.fit([context.selection, context.clipboard], route: route,
                                      fixed: [instructions, scaffold], images: images)
        var final = context
        final.selection = fitted.texts[0]
        final.clipboard = fitted.texts[1]
        if fitted.wasTruncated {
            Log.model.info("context truncated to fit the window")
        }
        return Prepared(route: route, prompt: prompt(for: action, context: final), wasTruncated: fitted.wasTruncated)
    }

    /// Each run is a fresh, single-turn session: actions don't share history.
    func start(_ action: LampoAction, context: TemplateContext, images: [CGImage] = [],
               routeOverride: ModelRoute? = nil) async throws -> Run {
        let prepared = try await prepare(action, context: context, images: images.count, routeOverride: routeOverride)
        let conversation = try model.makeConversation(route: prepared.route, instructions: instructions)
        let reasoning: ReasoningEffort? = prepared.route == .privateCloud ? (routeOverride == nil ? .light : .deep) : nil
        return Run(route: prepared.route, prompt: prepared.prompt, wasTruncated: prepared.wasTruncated,
                   stream: conversation.stream(ModelPrompt(prepared.prompt, images: images), reasoning: reasoning))
    }
}
