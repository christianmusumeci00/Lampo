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
        /// Set for translation actions: the detected source and the target.
        var translation: TranslationPair?
    }

    private let model: any ModelService
    private let preferences: Preferences
    private let budget: ContextBudget
    private let translator: any Translating

    init(model: any ModelService, preferences: Preferences, translator: any Translating = SystemTranslator()) {
        self.model = model
        self.preferences = preferences
        self.budget = ContextBudget(model: model)
        self.translator = translator
    }

    var instructions: String { SystemInstructions.action(language: preferences.responseLanguage) }

    func templateContext(selection: String?, clipboard: String?, app: String?) -> TemplateContext {
        TemplateContext(selection: selection, clipboard: clipboard, app: app,
                        language: SystemInstructions.languageName(preferences.responseLanguage),
                        tone: preferences.rewriteTone)
    }

    /// Remembers the tone picked in the Lens for the next "Rewrite".
    func rememberTone(_ tone: RewriteTone) { preferences.rewriteTone = tone }

    /// Remembers a target picked in the Lens: it becomes where your own language translates to.
    func rememberTranslationTarget(_ target: String) {
        if !TranslationPlanner.sameLanguage(target, preferences.userLanguage) {
            preferences.translationLanguage = target
        }
    }

    /// Languages to translate into, sorted by name in the UI language.
    func translationLanguages() async -> [String] {
        await translator.supportedLanguages()
            .sorted { TranslationPlanner.displayName($0).localizedStandardCompare(TranslationPlanner.displayName($1)) == .orderedAscending }
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
        empty.dictation = context.dictation.map { _ in "" }
        let scaffold = prompt(for: action, context: empty)
        let fitted = await budget.fit([context.selection, context.clipboard, context.dictation], route: route,
                                      fixed: [instructions, scaffold], images: images)
        var final = context
        final.selection = fitted.texts[0]
        final.clipboard = fitted.texts[1]
        final.dictation = fitted.texts[2]
        if fitted.wasTruncated {
            Log.model.info("context truncated to fit the window")
        }
        return Prepared(route: route, prompt: prompt(for: action, context: final), wasTruncated: fitted.wasTruncated)
    }

    /// Each run is a fresh, single-turn session: actions don't share history.
    /// - Parameter translationTarget: a target picked in the Lens, for translation actions.
    func start(_ action: LampoAction, context: TemplateContext, images: [CGImage] = [],
               routeOverride: ModelRoute? = nil, translationTarget: String? = nil) async throws -> Run {
        if let setting = action.translationTarget {
            return try await translate(context.selection ?? context.clipboard ?? "", setting: setting,
                                       override: translationTarget)
        }
        let prepared = try await prepare(action, context: context, images: images.count, routeOverride: routeOverride)
        let conversation = try model.makeConversation(route: prepared.route, instructions: instructions)
        let reasoning: ReasoningEffort? = prepared.route == .privateCloud ? (routeOverride == nil ? .light : .deep) : nil
        return Run(route: prepared.route, prompt: prepared.prompt, wasTruncated: prepared.wasTruncated,
                   stream: conversation.stream(ModelPrompt(prepared.prompt, images: images), reasoning: reasoning))
    }

    /// Translation actions use Apple's Translation framework, on this Mac, even without Apple
    /// Intelligence. The whole text is translated (no context window), line by line.
    private func translate(_ text: String, setting: String, override: String?) async throws -> Run {
        let pair = try TranslationPlanner.pair(for: text, setting: setting, override: override,
                                               userLanguage: preferences.userLanguage,
                                               otherLanguage: preferences.otherLanguage)
        let lines = TranslationLayout.lines(of: text)
        let translated = try await translator.translate(TranslationLayout.translatable(lines), pair: pair)
        try Task.checkCancellation()
        let result = TranslationLayout.join(lines, translations: translated)
        let stream = AsyncThrowingStream<String, Error> { continuation in
            continuation.yield(result)
            continuation.finish()
        }
        return Run(route: .onDevice, prompt: "", wasTruncated: false, stream: stream, translation: pair)
    }
}
