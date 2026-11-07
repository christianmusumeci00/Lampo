import Foundation
import Testing
@testable import Lampo

@MainActor
struct LensViewModelTests {
    let model = MockModelService()
    let pasteboard = MockPasteboard()
    let preferences = Preferences(defaults: makeTestDefaults())

    func makeLens(initial: UUID = BuiltInActions.formalID) -> LensViewModel {
        let selection = SelectionContext(text: "ciao come va", app: .textEdit, anchor: nil, element: nil, source: .clipboard)
        let actions = BuiltInActions.all.filter { $0.output != .openPanel }
        return LensViewModel(selection: selection, actions: actions, initialActionID: initial,
                             runner: ActionRunner(model: model, preferences: preferences), pasteboard: pasteboard)
    }

    @Test func startsWithTheTriggeredAction() async {
        model.chunks = ["\"Buongiorno", "\"Buongiorno, come sta?\""]
        let lens = makeLens()
        lens.start()
        await lens.task?.value
        #expect(lens.activeAction?.id == BuiltInActions.formalID)
        #expect(lens.phase == .done)
        #expect(lens.result == "Buongiorno, come sta?")
        #expect(lens.route == .onDevice)
        let prompt = model.conversations.last?.prompts.last
        #expect(prompt?.contains("<text>\nciao come va\n</text>") == true)
        #expect(prompt?.contains("formal") == true)
    }

    @Test func tabCyclesAndRegenerates() async {
        let lens = makeLens(initial: BuiltInActions.correctID)
        lens.start()
        await lens.task?.value
        lens.next()
        await lens.task?.value
        #expect(lens.activeAction?.id == BuiltInActions.formalID)
        #expect(model.makeConversationCalls == 2)   // fresh session per action
        lens.previous()
        lens.previous()
        await lens.task?.value
        #expect(lens.activeIndex == lens.actions.count - 1)
    }

    @Test func replaceHandsBackCleanText() async {
        model.chunks = ["Ecco il testo:\nBuongiorno."]
        let lens = makeLens()
        var replaced: String?
        lens.onReplace = { replaced = $0 }
        lens.replace()                    // not finished yet: ignored
        #expect(replaced == nil)
        lens.start()
        await lens.task?.value
        lens.replace()
        #expect(replaced == "Buongiorno.")
    }

    @Test func copyLeavesTheResultOnTheClipboard() async {
        let lens = makeLens()
        lens.start()
        await lens.task?.value
        lens.copy()
        #expect(pasteboard.contents == "Hello!")
    }

    @Test func modelUnavailableIsExplained() {
        model.availabilityValue = .modelNotReady
        let lens = makeLens()
        lens.start()
        #expect(lens.phase == .failed(ModelAvailability.modelNotReady.message))
        #expect(!lens.canReplace)
    }
}

@MainActor
struct PanelContextTests {
    let model = MockModelService()
    let preferences = Preferences(defaults: makeTestDefaults())

    func makeViewModel() -> PanelViewModel {
        PanelViewModel(model: model, preferences: preferences, pasteboard: MockPasteboard())
    }

    func selection(_ text: String) -> SelectionContext {
        SelectionContext(text: text, app: .textEdit, anchor: nil, element: nil, source: .accessibility)
    }

    @Test func selectionChipIsSentOnceWithTheQuestion() async {
        let vm = makeViewModel()
        vm.addContext(.selection(selection("The quick brown fox")))
        vm.query = "Translate to French"
        vm.submit()
        await vm.generationTask?.value

        let prompt = model.conversations.first?.prompts.first ?? ""
        #expect(prompt.contains("Selected text (selected in TextEdit):\n<text>\nThe quick brown fox\n</text>"))
        #expect(prompt.hasSuffix("Translate to French"))
        #expect(vm.contextItems.isEmpty)
        #expect(vm.currentTurn?.contextSummary == PanelViewModel.summary(.selection(selection("The quick brown fox"))))

        vm.query = "And to German?"
        vm.submit()
        await vm.generationTask?.value
        #expect(model.conversations.first?.prompts.last == "And to German?")
    }

    @Test func mathWithContextGoesToTheModel() async {
        let vm = makeViewModel()
        vm.addContext(.clipboard("numbers"))
        vm.query = "2+2"
        vm.submit()
        await vm.generationTask?.value
        #expect(vm.currentTurn?.kind == .model)
    }

    @Test func backspaceRemovesTheLastChipOnlyWhenEmpty() {
        let vm = makeViewModel()
        vm.addContext(.selection(selection("a")))
        vm.addContext(.clipboard("b"))
        vm.query = "x"
        #expect(!vm.removeLastContextIfQueryEmpty())
        vm.query = ""
        #expect(vm.removeLastContextIfQueryEmpty())
        #expect(vm.contextItems.count == 1)
        #expect(vm.contextItems.first?.isSelection == true)
    }

    @Test func onlyOneSelectionChip() {
        let vm = makeViewModel()
        vm.addContext(.selection(selection("a")))
        vm.addContext(.selection(selection("b")))
        #expect(vm.contextItems.count == 1)
    }

    @Test func insertReplacesTheSelectionTheAnswerIsAbout() async {
        let vm = makeViewModel()
        var inserted: (String, SelectionContext?)?
        vm.onInsert = { inserted = ($0, $1) }
        vm.addContext(.selection(selection("draft")))
        vm.query = "Improve"
        vm.submit()
        await vm.generationTask?.value
        vm.insertCurrentAnswer()
        #expect(inserted?.0 == "Hello!")
        #expect(inserted?.1?.text == "draft")
    }

    @Test func insertWithoutSelectionPastesAtCursor() async {
        let vm = makeViewModel()
        var target: SelectionContext?? = .none
        vm.onInsert = { _, selection in target = .some(selection) }
        vm.query = "Write a haiku"
        vm.submit()
        await vm.generationTask?.value
        vm.insertCurrentAnswer()
        #expect(target != nil)
        #expect(target! == nil)
    }

    @Test func explainActionRunsInThePanel() async throws {
        let vm = makeViewModel()
        let explain = try #require(BuiltInActions.all.first { $0.id == BuiltInActions.explainID })
        vm.runAction(explain, prompt: "Explain <text>x</text>", contextItems: [.selection(selection("x"))])
        await vm.generationTask?.value
        #expect(vm.currentTurn?.question == explain.name)
        #expect(model.conversations.last?.prompts == ["Explain <text>x</text>"])
        #expect(vm.activeSelection?.text == "x")
    }
}
