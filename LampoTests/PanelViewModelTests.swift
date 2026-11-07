import Foundation
import Testing
@testable import Lampo

@MainActor
struct PanelViewModelTests {
    let model = MockModelService()
    let pasteboard = MockPasteboard()
    let clock = TestClock()
    let preferences = Preferences(defaults: makeTestDefaults())

    func makeViewModel() -> PanelViewModel {
        let clock = self.clock
        return PanelViewModel(model: model, preferences: preferences, pasteboard: pasteboard, clock: { clock.now })
    }

    @Test func streamsAnswerOnDevice() async {
        let vm = makeViewModel()
        vm.panelWillAppear()
        vm.query = "  Say hello  "
        vm.submit()
        #expect(vm.query.isEmpty)
        #expect(vm.isGenerating)
        await vm.generationTask?.value

        let turn = try? #require(vm.currentTurn)
        #expect(turn?.question == "Say hello")
        #expect(turn?.answer == "Hello!")
        #expect(turn?.state == .done)
        #expect(turn?.route == .onDevice)
        #expect(model.conversations.first?.prompts == ["Say hello"])
    }

    @Test func calculatorSkipsTheModel() {
        let vm = makeViewModel()
        vm.query = "12 * 3"
        vm.submit()
        #expect(vm.currentTurn?.kind == .calculation)
        #expect(vm.currentTurn?.answer == Calculator.format(36))
        #expect(vm.currentTurn?.state == .done)
        #expect(model.makeConversationCalls == 0)
    }

    @Test func followUpsShareTheSession() async {
        let vm = makeViewModel()
        vm.query = "First"
        vm.submit()
        await vm.generationTask?.value
        vm.query = "Second"
        vm.submit()
        await vm.generationTask?.value
        #expect(model.makeConversationCalls == 1)
        #expect(model.conversations.first?.prompts == ["First", "Second"])
        #expect(vm.previousTurns.map(\.question) == ["First"])

        vm.goDeeper()
        await vm.generationTask?.value
        #expect(model.conversations.first?.prompts.last == SystemInstructions.goDeeper)
        #expect(vm.currentTurn?.isGoDeeper == true)
    }

    @Test func cancelKeepsPartialAnswer() async throws {
        model.chunks = ["A", "AB", "ABC", "ABCD"]
        model.delayPerChunk = .milliseconds(40)
        let vm = makeViewModel()
        vm.query = "Long"
        vm.submit()
        try await Task.sleep(for: .milliseconds(70))
        let task = vm.generationTask
        vm.cancel()
        await task?.value
        #expect(vm.currentTurn?.state == .cancelled)
        #expect(vm.currentTurn?.answer != "ABCD")
        #expect(!vm.isGenerating)
    }

    @Test func errorsBecomeHumanMessages() async {
        model.chunks = []
        model.failure = ModelError.guardrail
        let vm = makeViewModel()
        vm.query = "Bad"
        vm.submit()
        await vm.generationTask?.value
        #expect(vm.currentTurn?.state == .failed(ModelError.guardrail.localizedDescription))
    }

    @Test func unavailableModelExplainsWhy() {
        model.availabilityValue = .appleIntelligenceNotEnabled
        let vm = makeViewModel()
        vm.query = "Hi"
        vm.submit()
        #expect(vm.currentTurn?.state == .failed(ModelAvailability.appleIntelligenceNotEnabled.message))
        #expect(model.makeConversationCalls == 0)
    }

    @Test func sessionExpiresAfterFiveMinutesOfInactivity() async {
        let vm = makeViewModel()
        vm.query = "First"
        vm.submit()
        await vm.generationTask?.value

        clock.advance(.seconds(4 * 60))
        vm.panelWillAppear()
        #expect(vm.hasContent)

        clock.advance(.seconds(6 * 60))
        vm.panelWillAppear()
        #expect(!vm.hasContent)

        vm.query = "Again"
        vm.submit()
        await vm.generationTask?.value
        #expect(model.makeConversationCalls == 2)
    }

    @Test func copyWritesTheAnswer() async {
        preferences.closePanelAfterCopy = true
        let vm = makeViewModel()
        var closed = false
        vm.onRequestClose = { closed = true }
        vm.query = "Hi"
        vm.submit()
        await vm.generationTask?.value
        vm.copyCurrentAnswer()
        #expect(pasteboard.contents == "Hello!")
        #expect(closed)
    }

    @Test func thinkHarderIsBlockedWithoutCloud() async {
        let vm = makeViewModel()
        vm.query = "Hi"
        vm.submit()
        await vm.generationTask?.value
        #expect(!vm.canThinkHarder)   // this build has no PCC entitlement
        vm.thinkHarder()
        #expect(vm.currentTurn?.state == .failed(ModelError.privateCloudNotInBuild.localizedDescription))
        #expect(model.conversations.allSatisfy { $0.route == .onDevice })
    }

    @Test func newConversationClearsEverything() async {
        let vm = makeViewModel()
        vm.query = "Hi"
        vm.submit()
        await vm.generationTask?.value
        vm.resetConversation()
        #expect(!vm.hasContent)
        vm.query = "Again"
        vm.submit()
        await vm.generationTask?.value
        #expect(model.makeConversationCalls == 2)
    }
}
