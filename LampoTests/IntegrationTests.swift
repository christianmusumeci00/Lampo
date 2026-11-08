import Foundation
import Testing
@testable import Lampo

struct LampoURLTests {
    @Test func askWithQuestion() {
        #expect(LampoURL(URL(string: "lampo://ask?q=cosa%20significa%20ROI")!) == .ask("cosa significa ROI"))
        #expect(LampoURL(URL(string: "LAMPO://Ask?question=hi")!) == .ask("hi"))
        #expect(LampoURL(URL(string: "lampo:ask?q=hi")!) == .ask("hi"))
    }

    @Test func askWithoutQuestionOpensThePanel() {
        #expect(LampoURL(URL(string: "lampo://ask")!) == .ask(nil))
        #expect(LampoURL(URL(string: "lampo://ask?q=%20%20")!) == .ask(nil))
    }

    @Test func otherLinksAreIgnored() {
        #expect(LampoURL(URL(string: "lampo://run?action=x")!) == nil)
        #expect(LampoURL(URL(string: "https://ask?q=x")!) == nil)
    }

    @Test func longQuestionsAreCut() {
        let long = String(repeating: "a", count: 5000)
        guard case .ask(let question)? = LampoURL(URL(string: "lampo://ask?q=\(long)")!) else {
            Issue.record("expected ask"); return
        }
        #expect(question?.count == LampoURL.maxQuestionLength)
    }
}

@MainActor
struct ShortcutsServiceTests {
    let model = MockModelService()
    let preferences = Preferences(defaults: makeTestDefaults())
    let store = ActionStore(fileURL: FileManager.default.temporaryDirectory
        .appendingPathComponent("lampo-shortcuts-\(UUID().uuidString).json"))

    func makeService(history: HistoryStore? = nil) -> ShortcutsService {
        ShortcutsService(model: model, preferences: preferences, actionStore: store, history: history)
    }

    @Test func askAnswersOnDevice() async throws {
        let answer = try await makeService().ask("  Say hello ")
        #expect(answer == .init(text: "Hello!", route: .onDevice))
        #expect(model.conversations.first?.prompts == ["Say hello"])
    }

    @Test func askUsesTheCalculator() async throws {
        let answer = try await makeService().ask("12 * 3")
        #expect(answer.text == Calculator.format(36))
        #expect(model.conversations.isEmpty)
    }

    @Test func askRefusesWhenDisabledOrEmpty() async {
        let service = makeService()
        await #expect(throws: ShortcutsError.emptyText) { try await service.ask("   ") }
        preferences.isEnabled = false
        await #expect(throws: ShortcutsError.disabled) { try await service.ask("hi") }
    }

    @Test func askNeedsTheModel() async {
        model.availabilityValue = .appleIntelligenceNotEnabled
        await #expect(throws: ModelError.self) { try await makeService().ask("hi") }
    }

    @Test func runsATextAction() async throws {
        let answer = try await makeService().run(actionID: BuiltInActions.correctID, on: "ciao")
        #expect(answer?.text == "Hello!")
        #expect(model.conversations.first?.prompts.first?.contains("ciao") == true)
    }

    @Test func structuredActionsOpenTheCard() async throws {
        let service = makeService()
        var shown: (DraftKind, String)?
        service.showDraft = { shown = ($0, $1) }
        let answer = try await service.run(actionID: BuiltInActions.createEventID, on: "cena giovedì alle 20")
        #expect(answer == nil)
        #expect(shown?.0 == .event)
        #expect(shown?.1 == "cena giovedì alle 20")
        #expect(model.conversations.isEmpty)
    }

    @Test func screenActionsAndMissingActionsFail() async {
        let service = makeService()
        await #expect(throws: ShortcutsError.needsScreen) { try await service.run(actionID: BuiltInActions.askScreenID, on: "x") }
        await #expect(throws: ShortcutsError.actionNotFound) { try await service.run(actionID: UUID(), on: "x") }
        await #expect(throws: ShortcutsError.emptyText) { try await service.run(actionID: BuiltInActions.correctID, on: " ") }
    }

    @Test func resultsGoToTheHistoryWhenOn() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("lampo-h-\(UUID().uuidString).json")
        let history = HistoryStore(fileURL: url, isEnabled: { true })
        _ = try await makeService(history: history).ask("Say hello")
        #expect(history.entries.map(\.output) == ["Hello!"])
    }
}
