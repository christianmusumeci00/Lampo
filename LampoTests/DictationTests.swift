import Foundation
import KeyboardShortcuts
import Testing
@testable import Lampo

@MainActor
final class DictationHarness {
    let engine = MockDictationEngine()
    let model = MockModelService()
    let pasteboard = MockPasteboard()
    let keystrokes: MockKeystrokes
    let permissions = MockPermissions()
    let hotkeys = MockHotkeyBackend()
    let preferences = Preferences(defaults: makeTestDefaults())
    var now = ContinuousClock.now
    let controller: DictationController
    var needsModel = 0
    var hudVisible: [Bool] = []
    var results: [(input: String, output: String)] = []

    init() {
        keystrokes = MockKeystrokes(pasteboard: pasteboard)
        let output = OutputService(accessibility: MockAccessibility(), clipboard: makeBridge(pasteboard, keystrokes),
                                   pasteboard: pasteboard, activate: { _ in })
        var clockBox: (() -> ContinuousClock.Instant)!
        controller = DictationController(
            engine: engine, runner: ActionRunner(model: model, preferences: preferences, translator: MockTranslator()),
            output: output, permissions: permissions, hotkeys: hotkeys, statusHUD: HUDController(),
            language: { "it" }, clock: { clockBox() })
        clockBox = { [unowned self] in self.now }
        controller.onNeedsModel = { [unowned self] in self.needsModel += 1 }
        controller.onShowHUD = { [unowned self] in self.hudVisible.append($0) }
        controller.onResult = { [unowned self] _, input, output, _ in self.results.append((input, output)) }
    }

    var dictate: LampoAction { BuiltInActions.all.first { $0.id == BuiltInActions.dictateID }! }

    func settle() async {
        await controller.work?.value
        await controller.work?.value
    }
}

@MainActor
struct DictationControllerTests {
    @Test func tapStartsAndASecondPressInsertsTheCleanedText() async {
        let h = DictationHarness()
        h.model.chunks = ["Allora, domani non vengo."]
        h.controller.keyDown(h.dictate)
        await h.settle()
        #expect(h.controller.phase == .listening)
        #expect(h.engine.started == ["it"])
        #expect(h.hudVisible == [true])
        #expect(h.hotkeys.handlers[.cancelDictation] != nil)

        h.now += .milliseconds(120)           // a quick tap: keep listening
        h.controller.keyUp(h.dictate.id)
        #expect(h.controller.phase == .listening)

        h.controller.keyDown(h.dictate)        // second press: stop
        await h.settle()
        #expect(h.controller.phase == .idle)
        #expect(h.engine.stops == 1)
        #expect(h.keystrokes.pastedTexts == ["Allora, domani non vengo."])
        #expect(h.hotkeys.handlers[.cancelDictation] == nil)
        #expect(h.results.first?.input == "ehm allora domani non vengo")
        let prompt = h.model.conversations.last?.prompts.last ?? ""
        #expect(prompt.contains("<text>\nehm allora domani non vengo\n</text>"))
        #expect(prompt.contains("hesitations"))
    }

    @Test func holdingIsPushToTalk() async {
        let h = DictationHarness()
        h.model.chunks = ["Domani non vengo."]
        h.controller.keyDown(h.dictate)
        await h.settle()
        h.now += .milliseconds(900)
        h.controller.keyUp(h.dictate.id)
        await h.settle()
        #expect(h.engine.stops == 1)
        #expect(h.keystrokes.pastedTexts == ["Domani non vengo."])
    }

    @Test func releaseBeforeListeningStillStops() async {
        let h = DictationHarness()
        h.controller.keyDown(h.dictate)
        h.now += .milliseconds(900)
        h.controller.keyUp(h.dictate.id)      // still starting
        await h.settle()
        await h.settle()
        #expect(h.engine.stops == 1)
        #expect(h.controller.phase == .idle)
    }

    @Test func escapeCancelsWithoutTyping() async {
        let h = DictationHarness()
        h.controller.keyDown(h.dictate)
        await h.settle()
        h.hotkeys.press(.cancelDictation)
        await h.settle()
        #expect(h.engine.cancels == 1)
        #expect(h.engine.stops == 0)
        #expect(h.keystrokes.pastedTexts.isEmpty)
        #expect(h.controller.phase == .idle)
        #expect(h.hotkeys.handlers[.cancelDictation] == nil)
    }

    @Test func withoutTheModelTheTranscriptIsInsertedAsSaid() async {
        let h = DictationHarness()
        h.model.availabilityValue = .appleIntelligenceNotEnabled
        h.engine.transcript = "Domani non vengo"
        h.controller.keyDown(h.dictate)
        await h.settle()
        h.controller.finish()
        await h.settle()
        #expect(h.keystrokes.pastedTexts == ["Domani non vengo"])
    }

    @Test func withoutAccessibilityTheTextIsCopied() async {
        let h = DictationHarness()
        h.permissions.isAccessibilityGranted = false
        h.model.chunks = ["Domani non vengo."]
        h.controller.keyDown(h.dictate)
        await h.settle()
        h.controller.finish()
        await h.settle()
        #expect(h.keystrokes.pastedTexts.isEmpty)
        #expect(h.pasteboard.contents == "Domani non vengo.")
    }

    @Test func silenceInsertsNothing() async {
        let h = DictationHarness()
        h.engine.transcript = ""
        h.controller.keyDown(h.dictate)
        await h.settle()
        h.controller.finish()
        await h.settle()
        #expect(h.keystrokes.pastedTexts.isEmpty)
        #expect(h.model.makeConversationCalls == 0)
        #expect(h.controller.phase == .idle)
    }

    @Test func deniedMicrophoneDoesntListen() async {
        let h = DictationHarness()
        h.engine.microphoneAccess = .notDetermined
        h.engine.grantsMicrophone = false
        h.controller.keyDown(h.dictate)
        await h.settle()
        #expect(h.engine.started.isEmpty)
        #expect(h.controller.phase == .idle)
    }

    @Test func grantingTheMicrophoneKeepsListeningUntilTheNextPress() async {
        let h = DictationHarness()
        h.engine.microphoneAccess = .notDetermined
        h.controller.keyDown(h.dictate)
        await h.settle()
        h.now += .seconds(5)                   // the release happened while the prompt was up
        h.controller.keyUp(h.dictate.id)
        #expect(h.controller.phase == .listening)
    }

    @Test func missingModelAsksToDownload() async {
        let h = DictationHarness()
        h.engine.readinessValue = .needsDownload
        h.controller.keyDown(h.dictate)
        await h.settle()
        #expect(h.needsModel == 1)
        #expect(h.engine.started.isEmpty)
        #expect(h.engine.downloads.isEmpty)   // never without the user's yes
    }

    @Test func emptyPromptKeepsTheWordsAsSaid() async {
        let h = DictationHarness()
        var raw = h.dictate
        raw.promptTemplate = ""
        h.engine.transcript = "ciao a tutti"
        h.controller.keyDown(raw)
        await h.settle()
        h.controller.finish()
        await h.settle()
        #expect(h.keystrokes.pastedTexts == ["ciao a tutti"])
        #expect(h.model.makeConversationCalls == 0)
    }

    @Test func dictatedEventsOpenTheCard() async {
        let h = DictationHarness()
        var event = h.dictate
        event.output = .calendarEvent
        var drafted: (DraftKind, String)?
        h.controller.onShowDraft = { drafted = ($0, $1) }
        h.engine.transcript = "cena con Marco giovedì alle 20"
        h.controller.keyDown(event)
        await h.settle()
        h.controller.finish()
        await h.settle()
        #expect(drafted?.0 == .event)
        #expect(drafted?.1 == "cena con Marco giovedì alle 20")
        #expect(h.keystrokes.pastedTexts.isEmpty)
    }
}

@MainActor
struct DictationActionTests {
    @Test func dictateIsOnWithItsShortcut() {
        let store = ActionStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("LampoTests-\(UUID().uuidString)").appendingPathComponent("actions.json"))
        let dictate = store.action(id: BuiltInActions.dictateID)
        #expect(dictate?.isEnabled == true)
        #expect(dictate?.isDictation == true)
        #expect(dictate?.effectiveOutput == .replaceSilently)
        #expect(BuiltInActions.defaultShortcuts[BuiltInActions.dictateID] == .init(.d, modifiers: [.option, .shift]))
        #expect(!store.selectionActions.contains { $0.id == BuiltInActions.dictateID })
    }

    @Test func previewMeansInsertForDictation() {
        var action = LampoAction(name: "D", symbol: "mic", promptTemplate: "Clean {{dictation}}", input: .dictation, output: .preview)
        #expect(action.effectiveOutput == .replaceSilently)
        action.output = .copy
        #expect(action.effectiveOutput == .copy)
    }

    @Test func dictationVariableIsFenced() {
        var context = TemplateContext(selection: nil, clipboard: nil, app: nil, language: "Italian")
        context.dictation = "ciao"
        #expect(PromptTemplate.render("Clean {{dictation}}", context: context, input: .dictation) == "Clean <text>\nciao\n</text>")
        #expect(PromptTemplate.render("Make it formal", context: context, input: .dictation) == "Make it formal\n\n<text>\nciao\n</text>")
    }

    @Test func newBuiltInsGoAfterTheirPredecessor() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("LampoTests-\(UUID().uuidString)").appendingPathComponent("actions.json")
        // Lampo 1.1 without Dictate, Reply and Extract.
        let added: Set<UUID> = [BuiltInActions.dictateID, BuiltInActions.replyID, BuiltInActions.extractID]
        let old = ActionStore(fileURL: url, builtIns: { BuiltInActions.all.filter { !added.contains($0.id) } })
        old.add(LampoAction(name: "Mine", symbol: "star", promptTemplate: "P"))
        let updated = ActionStore(fileURL: url)
        let ids = updated.actions.map(\.id)
        let translate = try #require(ids.firstIndex(of: BuiltInActions.translateID))
        #expect(ids[translate + 1] == BuiltInActions.replyID)
        #expect(ids[translate + 2] == BuiltInActions.dictateID)
        let reminder = try #require(ids.firstIndex(of: BuiltInActions.createReminderID))
        #expect(ids[reminder + 1] == BuiltInActions.extractID)
        #expect(updated.actions.last?.name == "Mine")
    }

    @Test func coordinatorHandsDictationToTheController() async {
        let store = ActionStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("LampoTests-\(UUID().uuidString)").appendingPathComponent("actions.json"))
        let pasteboard = MockPasteboard()
        let keystrokes = MockKeystrokes(pasteboard: pasteboard)
        let accessibility = MockAccessibility()
        let bridge = makeBridge(pasteboard, keystrokes)
        let coordinator = ActionCoordinator(
            store: store, runner: ActionRunner(model: MockModelService(), preferences: Preferences(defaults: makeTestDefaults())),
            selectionReader: SelectionService(accessibility: accessibility, clipboard: bridge),
            output: OutputService(accessibility: accessibility, clipboard: bridge, pasteboard: pasteboard, activate: { _ in }),
            permissions: MockPermissions(), pasteboard: pasteboard, screenCapture: MockScreenCapture(),
            routingPolicy: { RoutingPolicy(onlyOnMac: true, privateCloudInBuild: false) },
            lens: LensController(), hud: HUDController(), panel: nil)
        var dictated: [UUID] = []
        coordinator.onDictate = { dictated.append($0.id) }
        coordinator.perform(BuiltInActions.dictateID)
        for _ in 0..<5 { await Task.yield() }
        #expect(dictated == [BuiltInActions.dictateID])
    }

    @Test func hotkeyReleaseReachesKeyUpHandlers() {
        let backend = MockHotkeyBackend()
        let manager = HotkeyManager(backend: backend, isEnabled: true)
        let name = KeyboardShortcuts.Name("action-test-dictate")
        var released: [String] = []
        manager.sync([name], prefix: "action-", action: { _ in }, keyUp: { released.append($0.rawValue) })
        backend.release(name)
        #expect(released == ["action-test-dictate"])
    }
}
