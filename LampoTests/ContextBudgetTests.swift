import CoreGraphics
import Foundation
import Testing
@testable import Lampo

/// Token budget and truncation, with a mock `tokenCount` (one token per word).
@MainActor
struct ContextBudgetTests {
    let model = MockModelService()

    func words(_ count: Int, prefix: String = "w") -> String {
        (1...count).map { "\(prefix)\($0)" }.joined(separator: " ")
    }

    @Test func shortTextIsUntouched() async {
        let budget = ContextBudget(model: model)
        let fitted = await budget.fit(["hello there", nil], route: .onDevice, fixed: ["instructions"])
        #expect(fitted == ContextBudget.Fitted(texts: ["hello there", nil], wasTruncated: false))
    }

    @Test func longTextKeepsBeginningAndEnd() async throws {
        model.contextSizeValue = 2000
        let budget = ContextBudget(model: model)
        let text = words(5000)
        let fitted = await budget.fit([text], route: .onDevice, fixed: ["a b c"])
        let excerpt = try #require(fitted.texts[0])

        #expect(fitted.wasTruncated)
        #expect(excerpt.hasPrefix("w1 w2 w3"))
        #expect(excerpt.hasSuffix("w4999 w5000"))
        #expect(excerpt.contains(ContextBudget.gap))
        // Fits what's left after the fixed text and the answer reserve.
        let limit = 2000 - 3 - ContextBudget.answerReserve
        let tokens = try await model.tokenCount(excerpt)
        #expect(tokens <= limit)
        #expect(tokens > limit / 2)
    }

    @Test func imagesAndHistoryReduceTheRoom() async {
        model.contextSizeValue = 3000
        let budget = ContextBudget(model: model)
        let text = words(1500)
        let withoutImage = await budget.fit([text], route: .onDevice, fixed: [])
        #expect(!withoutImage.wasTruncated)
        let withImage = await budget.fit([text], route: .onDevice, fixed: [], images: 1)
        #expect(withImage.wasTruncated)
        let withHistory = await budget.fit([text], route: .onDevice, fixed: [words(800)])
        #expect(withHistory.wasTruncated)
    }

    @Test func twoTextsShareTheRoomByTheirSize() async throws {
        model.contextSizeValue = 2000
        let budget = ContextBudget(model: model)
        let fitted = await budget.fit([words(3000, prefix: "s"), words(1000, prefix: "c")], route: .onDevice, fixed: [])
        let selection = try #require(fitted.texts[0])
        let clipboard = try #require(fitted.texts[1])
        let selectionTokens = try await model.tokenCount(selection)
        let clipboardTokens = try await model.tokenCount(clipboard)
        #expect(selectionTokens + clipboardTokens <= 2000 - ContextBudget.answerReserve)
        #expect(selectionTokens > clipboardTokens * 2)
    }

    @Test func estimatesWhenTheModelCannotCount() async {
        model.tokenCountFails = true
        model.contextSizeValue = 1500
        let budget = ContextBudget(model: model)
        let text = String(repeating: "abcdef ", count: 2000)   // 14 000 bytes ≈ 4667 estimated tokens
        let fitted = await budget.fit([text], route: .onDevice, fixed: [])
        #expect(fitted.wasTruncated)
        #expect(ContextBudget.estimate(fitted.texts[0] ?? "") <= 500)
    }

    @Test func excerptCutsAtWordBoundaries() {
        let excerpt = ContextBudget.excerpt("alpha beta gamma delta epsilon zeta eta theta", keeping: 25)
        #expect(excerpt == "alpha beta gamma" + ContextBudget.gap + "eta theta")
        #expect(ContextBudget.excerpt("short", keeping: 100) == "short")
    }
}

@MainActor
struct ActionRunnerBudgetTests {
    let model = MockModelService()
    let preferences = Preferences(defaults: makeTestDefaults())

    @Test func longSelectionIsTruncatedAndFlagged() async throws {
        model.contextSizeValue = 1500
        let runner = ActionRunner(model: model, preferences: preferences)
        let text = (1...4000).map { "parola\($0)" }.joined(separator: " ")
        let action = try #require(BuiltInActions.all.first { $0.id == BuiltInActions.summarizeID })
        let run = try await runner.start(action, context: runner.templateContext(selection: text, clipboard: nil, app: nil))
        #expect(run.wasTruncated)
        #expect(run.prompt.contains("parola1 parola2"))
        #expect(run.prompt.contains("parola4000"))
        #expect(run.prompt.contains("[…]"))
        #expect(!run.prompt.contains("parola2000 "))
    }

    @Test func truncatedSelectionCannotBeReplacedInTheLens() async {
        model.contextSizeValue = 1500
        let text = (1...4000).map { "parola\($0)" }.joined(separator: " ")
        let selection = SelectionContext(text: text, app: .textEdit, anchor: nil, element: nil, source: .accessibility)
        let lens = LensViewModel(selection: selection, actions: BuiltInActions.all, initialActionID: BuiltInActions.correctID,
                                 runner: ActionRunner(model: model, preferences: preferences), pasteboard: MockPasteboard())
        lens.start()
        await lens.task?.value
        #expect(lens.phase == .done)
        #expect(lens.wasTruncated)
        #expect(!lens.canReplace)
        #expect(!lens.canThinkHarder)   // no Private Cloud Compute in this build
    }
}

@MainActor
struct WindowContextTests {
    let model = MockModelService()
    let capture = MockScreenCapture()
    let preferences = Preferences(defaults: makeTestDefaults())

    func makeViewModel() -> PanelViewModel {
        PanelViewModel(model: model, preferences: preferences, pasteboard: MockPasteboard(), screenCapture: capture)
    }

    @Test func windowChipSendsTheScreenshotWithTheQuestion() async {
        let vm = makeViewModel()
        vm.toggleWindow(from: .terminal, permitted: true)
        await waitUntil { vm.hasWindowContext }
        #expect(vm.contextItems.first?.summary.contains("Terminal") == true)

        vm.query = "cosa significa?"
        vm.submit()
        await vm.generationTask?.value

        let conversation = model.conversations.first
        #expect(conversation?.imageCounts == [1])
        let prompt = conversation?.prompts.first ?? ""
        #expect(prompt.contains("screenshot of the user's Terminal window titled “main.swift”"))
        #expect(prompt.hasSuffix("cosa significa?"))
        // The context is English and the model is small: the answer language is stated.
        #expect(prompt.contains("Answer in Italian."))
        #expect(vm.contextItems.isEmpty)
        #expect(vm.currentTurn?.state == .done)

        // Follow-ups don't resend the image: the session already has it.
        vm.query = "e come lo risolvo?"
        vm.submit()
        await vm.generationTask?.value
        #expect(conversation?.imageCounts == [1, 0])
    }

    @Test func secondShortcutRemovesTheWindow() async {
        let vm = makeViewModel()
        vm.toggleWindow(from: .terminal, permitted: true)
        await waitUntil { vm.hasWindowContext }
        vm.toggleWindow(from: .terminal, permitted: true)
        #expect(!vm.hasWindowContext)
        #expect(capture.captures == 1)
    }

    @Test func missingPermissionShowsAnActionableNotice() {
        let vm = makeViewModel()
        var granted: [PermissionKind] = []
        vm.onGrantPermission = { granted.append($0) }
        vm.toggleWindow(from: .terminal, permitted: false)
        #expect(vm.notice == .permission(.screenRecording))
        #expect(capture.captures == 0)
        vm.grantPermission(.screenRecording)
        #expect(granted == [.screenRecording])
    }

    @Test func captureFailureIsExplained() async {
        capture.error = .noWindow
        let vm = makeViewModel()
        vm.toggleWindow(from: .terminal, permitted: true)
        await waitUntil { !vm.isCapturingWindow }
        #expect(vm.notice == .message(ScreenCaptureError.noWindow.localizedDescription))
        #expect(!vm.hasWindowContext)
    }

    @Test func askTheScreenWaitsForTheQuestion() async throws {
        let vm = makeViewModel()
        let shot = try await capture.captureFrontWindow(of: .terminal)
        vm.prepareScreenQuestion(shot)
        #expect(vm.hasWindowContext)
        #expect(model.conversations.allSatisfy { $0.prompts.isEmpty })
        let action = try #require(BuiltInActions.all.first { $0.id == BuiltInActions.askScreenID })
        #expect(action.input == .screen)
        #expect(action.promptTemplate.isEmpty)
    }

    @Test func longSelectionInThePanelIsTruncated() async {
        model.contextSizeValue = 1500
        let vm = makeViewModel()
        let text = (1...4000).map { "parola\($0)" }.joined(separator: " ")
        vm.addContext(.selection(SelectionContext(text: text, app: .textEdit, anchor: nil, element: nil, source: .accessibility)))
        vm.query = "Riassumi"
        vm.submit()
        await vm.generationTask?.value
        #expect(vm.currentTurn?.wasTruncated == true)
        let prompt = model.conversations.first?.prompts.first ?? ""
        #expect(prompt.contains("[…]"))
        #expect(prompt.hasSuffix("Riassumi"))
    }

    @Test func captureSizeIsCappedAt1600Pixels() {
        #expect(ScreenCaptureService.targetSize(points: CGSize(width: 1440, height: 900), scale: 2)
                == CGSize(width: 1600, height: 1000))
        #expect(ScreenCaptureService.targetSize(points: CGSize(width: 600, height: 400), scale: 2)
                == CGSize(width: 1200, height: 800))
        #expect(ScreenCaptureService.targetSize(points: CGSize(width: 800, height: 2000), scale: 1)
                == CGSize(width: 640, height: 1600))
    }
}
