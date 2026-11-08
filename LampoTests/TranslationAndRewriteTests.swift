import Foundation
import Testing
@testable import Lampo

struct TranslationPlannerTests {
    let italian = "Ciao Marco, ci vediamo giovedì sera per la cena con gli amici."
    let english = "Hi Marco, see you on Thursday evening for dinner with our friends."

    @Test func automaticTranslatesIntoYourLanguage() throws {
        let pair = try TranslationPlanner.pair(for: english, setting: TranslationPlanner.automatic, override: nil,
                                               userLanguage: "it", otherLanguage: "en")
        #expect(pair == TranslationPair(source: "en", target: "it"))
    }

    @Test func automaticSendsYourLanguageToTheOtherOne() throws {
        let pair = try TranslationPlanner.pair(for: italian, setting: TranslationPlanner.automatic, override: nil,
                                               userLanguage: "it", otherLanguage: "de")
        #expect(pair == TranslationPair(source: "it", target: "de"))
    }

    @Test func fixedTargetAndLensOverride() throws {
        let fixed = try TranslationPlanner.pair(for: italian, setting: "fr", override: nil,
                                                userLanguage: "it", otherLanguage: "en")
        #expect(fixed.target == "fr")
        let picked = try TranslationPlanner.pair(for: italian, setting: "fr", override: "es",
                                                 userLanguage: "it", otherLanguage: "en")
        #expect(picked.target == "es")
    }

    @Test func refusesTheSameLanguage() {
        #expect(throws: TranslationFailure.self) {
            try TranslationPlanner.pair(for: italian, setting: "it", override: nil, userLanguage: "it", otherLanguage: "en")
        }
        #expect(throws: TranslationFailure.unknownLanguage) {
            try TranslationPlanner.pair(for: "?", setting: "en", override: nil, userLanguage: "it", otherLanguage: "en")
        }
    }

    @Test func sameLanguageIgnoresRegions() {
        #expect(TranslationPlanner.sameLanguage("en", "en-GB"))
        #expect(!TranslationPlanner.sameLanguage("en", "it"))
        #expect(!TranslationPlanner.sameLanguage("zh-Hans", "zh-Hant"))
    }

    @Test func otherLanguageComesFromTheMacsLanguages() {
        #expect(TranslationPlanner.defaultOtherLanguage(userLanguage: "it", preferred: ["it-IT", "en-US"]) == "en")
        #expect(TranslationPlanner.defaultOtherLanguage(userLanguage: "it", preferred: ["it-IT", "de-DE"]) == "de")
        #expect(TranslationPlanner.defaultOtherLanguage(userLanguage: "it", preferred: ["it-IT"]) == "en")
        #expect(TranslationPlanner.defaultOtherLanguage(userLanguage: "en", preferred: ["en-US"]) == "it")
    }

    @Test func oneEntryPerLanguage() {
        let unique = SystemTranslator.uniqueLanguages(["en-Latn-US", "en-Latn-GB", "it-Latn-IT", "zh-Hans-CN", "zh-Hant-TW"])
        #expect(unique == ["en", "it", "zh-Hans", "zh-Hant"])
    }

    @Test func layoutKeepsBlankLinesAndIndentation() {
        let text = "Titolo\n\n  - primo punto\n  - secondo\n"
        let lines = TranslationLayout.lines(of: text)
        let translatable = TranslationLayout.translatable(lines)
        #expect(translatable == ["Titolo", "- primo punto", "- secondo"])
        let joined = TranslationLayout.join(lines, translations: ["Title", "- first point", "- second"])
        #expect(joined == "Title\n\n  - first point\n  - second\n")
    }
}

@MainActor
struct TranslateActionTests {
    let model = MockModelService()
    let translator = MockTranslator()
    let preferences = Preferences(defaults: makeTestDefaults())
    var translate: LampoAction { BuiltInActions.all.first { $0.id == BuiltInActions.translateID }! }

    @Test func translateUsesAppleTranslationNotTheModel() async throws {
        model.availabilityValue = .appleIntelligenceNotEnabled
        preferences.responseLanguage = .italian
        let runner = ActionRunner(model: model, preferences: preferences, translator: translator)
        let text = "Hi Marco, see you on Thursday evening for dinner.\n\nBring the wine!"
        let run = try await runner.start(translate, context: runner.templateContext(selection: text, clipboard: nil, app: nil))
        var output = ""
        for try await chunk in run.stream { output = chunk }
        #expect(output == "[it] HI MARCO, SEE YOU ON THURSDAY EVENING FOR DINNER.\n\n[it] BRING THE WINE!")
        #expect(run.translation == TranslationPair(source: "en", target: "it"))
        #expect(model.makeConversationCalls == 0)
    }

    @Test func pickingATargetInTheLensIsRemembered() async throws {
        preferences.responseLanguage = .italian
        let runner = ActionRunner(model: model, preferences: preferences, translator: translator)
        let selection = SelectionContext(text: "Ciao Marco, ci vediamo giovedì sera per la cena.", app: .textEdit,
                                         anchor: nil, element: nil, source: .accessibility)
        let lens = LensViewModel(selection: selection, actions: [translate], initialActionID: translate.id,
                                 runner: runner, pasteboard: MockPasteboard())
        lens.start()
        await lens.task?.value
        #expect(lens.translation?.target == preferences.otherLanguage)

        lens.setTranslationTarget("de")
        await lens.task?.value
        #expect(lens.translation == TranslationPair(source: "it", target: "de"))
        #expect(lens.result.hasPrefix("[de] CIAO MARCO"))
        #expect(preferences.translationLanguage == "de")
        #expect(lens.canReplace)

        await lens.loadTranslationLanguages()
        #expect(lens.translationLanguages.count == translator.languages.count)
    }

    @Test func translationErrorsShowInTheLens() async {
        translator.failure = TranslationFailure.notDownloaded("tedesco")
        preferences.responseLanguage = .italian
        let runner = ActionRunner(model: model, preferences: preferences, translator: translator)
        let selection = SelectionContext(text: "Ciao Marco, ci vediamo giovedì sera per la cena.", app: .textEdit,
                                         anchor: nil, element: nil, source: .accessibility)
        let lens = LensViewModel(selection: selection, actions: [translate], initialActionID: translate.id,
                                 runner: runner, pasteboard: MockPasteboard())
        lens.start()
        await lens.task?.value
        guard case .failed(let message) = lens.phase else {
            Issue.record("expected a failure, got \(lens.phase)")
            return
        }
        #expect(message.contains("tedesco"))
    }
}

@MainActor
struct RewriteToneTests {
    let model = MockModelService()
    let defaults = makeTestDefaults()
    var preferences: Preferences
    var rewrite: LampoAction { BuiltInActions.all.first { $0.id == BuiltInActions.rewriteID }! }

    init() { preferences = Preferences(defaults: defaults) }

    @Test func toneFillsThePromptAndIsRemembered() async {
        let runner = ActionRunner(model: model, preferences: preferences, translator: MockTranslator())
        let selection = SelectionContext(text: "ciao, domani non posso venire", app: .textEdit,
                                         anchor: nil, element: nil, source: .accessibility)
        let lens = LensViewModel(selection: selection, actions: [rewrite], initialActionID: rewrite.id,
                                 runner: runner, pasteboard: MockPasteboard())
        #expect(rewrite.usesTone)
        #expect(lens.tone == .clearer)
        lens.start()
        await lens.task?.value
        #expect(model.conversations.last?.prompts.last?.contains(RewriteTone.clearer.instruction) == true)

        lens.setTone(.formal)
        await lens.task?.value
        #expect(model.conversations.last?.prompts.last?.contains(RewriteTone.formal.instruction) == true)
        #expect(preferences.rewriteTone == .formal)
        #expect(Preferences(defaults: defaults).rewriteTone == .formal)
    }

    @Test func onlyRewriteAndTranslateShowOptions() {
        let toned = BuiltInActions.all.filter(\.usesTone).map(\.id)
        let translating = BuiltInActions.all.filter(\.isTranslation).map(\.id)
        #expect(toned == [BuiltInActions.rewriteID])
        #expect(translating == [BuiltInActions.translateID])
    }
}

@MainActor
struct ActionLineupTests {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("LampoTests-\(UUID().uuidString)").appendingPathComponent("actions.json")

    @Test func newInstallsTurnOnTheDistinctActions() {
        let store = ActionStore(fileURL: url)
        #expect(store.enabledActions.map(\.id) == [
            BuiltInActions.correctID, BuiltInActions.rewriteID, BuiltInActions.translateID,
            BuiltInActions.dictateID, BuiltInActions.askScreenID, BuiltInActions.createEventID, BuiltInActions.createReminderID,
            BuiltInActions.explainID,
        ])
        #expect(store.selectionActions.allSatisfy { $0.isEnabled })
        #expect(store.action(id: BuiltInActions.toEnglishID) == nil)
    }

    /// A version-1 file, as Lampo 1.0 wrote it: no `isEnabled`, no `translationTarget`.
    private func writeVersion1File(extra: [String] = []) throws {
        let ids = [BuiltInActions.correctID, BuiltInActions.formalID, BuiltInActions.shorterID,
                   BuiltInActions.toEnglishID, BuiltInActions.toItalianID, BuiltInActions.summarizeID,
                   BuiltInActions.explainID, BuiltInActions.askScreenID, BuiltInActions.createEventID,
                   BuiltInActions.createReminderID]
        let entries = ids.map { id in
            """
            {"id":"\(id.uuidString)","name":"N","symbol":"star","promptTemplate":"P {{selection}}",
             "input":"selection","output":"preview","route":"onDevice","isBuiltIn":true}
            """
        } + extra
        let json = #"{"version":1,"deletedBuiltIns":[],"actions":["# + entries.joined(separator: ",") + "]}"
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(json.utf8).write(to: url)
    }

    @Test func version1InstallsTurnOffTheDuplicatesWithoutDeletingThem() throws {
        let custom = UUID()
        try writeVersion1File(extra: ["""
            {"id":"\(custom.uuidString)","name":"Mine","symbol":"star","promptTemplate":"P",
             "input":"selection","output":"copy","route":"onDevice","isBuiltIn":false}
            """])
        let store = ActionStore(fileURL: url)
        let off: Set<UUID> = [BuiltInActions.formalID, BuiltInActions.shorterID, BuiltInActions.summarizeID,
                              BuiltInActions.toEnglishID, BuiltInActions.toItalianID]
        #expect(Set(store.actions.filter { !$0.isEnabled }.map(\.id)) == off)
        #expect(store.action(id: custom)?.isEnabled == true)
        #expect(store.actions.map(\.id).prefix(3) == [BuiltInActions.correctID, BuiltInActions.rewriteID,
                                                     BuiltInActions.translateID])
        #expect(store.actions.count == 14)

        // Migrated once: turning one back on sticks.
        var formal = try #require(store.action(id: BuiltInActions.formalID))
        formal.isEnabled = true
        store.update(formal)
        #expect(ActionStore(fileURL: url).action(id: BuiltInActions.formalID)?.isEnabled == true)
    }

    @Test func togglingAnActionResyncsHotkeys() throws {
        let store = ActionStore(fileURL: url)
        var calls = 0
        store.onActionsAddedOrRemoved = { calls += 1 }
        var summarize = try #require(store.action(id: BuiltInActions.summarizeID))
        summarize.name = "Riassunto"
        store.update(summarize)
        #expect(calls == 0)
        summarize.isEnabled = true
        store.update(summarize)
        #expect(calls == 1)
        #expect(store.selectionActions.contains { $0.id == BuiltInActions.summarizeID })
    }
}
