import Foundation
import Testing
@testable import Lampo

@MainActor
struct HistoryStoreTests {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("lampo-history-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("history.json")

    final class Flag { var on: Bool; init(_ on: Bool) { self.on = on } }

    @Test func offByDefaultRecordsNothing() {
        let preferences = Preferences(defaults: makeTestDefaults())
        #expect(preferences.keepHistory == false)
        let store = HistoryStore(fileURL: url, isEnabled: { preferences.keepHistory })
        store.record(source: "Panel", input: "q", output: "a", route: .onDevice)
        #expect(store.entries.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func recordsNewestFirstAndPersists() {
        let store = HistoryStore(fileURL: url, isEnabled: { true })
        store.record(source: "Panel", input: "first", output: "one", route: .onDevice)
        store.record(source: "Correct", input: "second", output: "two", route: .onDevice)
        store.record(source: "Panel", input: "empty", output: "   ", route: .onDevice)
        #expect(store.entries.map(\.input) == ["second", "first"])

        let reloaded = HistoryStore(fileURL: url, isEnabled: { true })
        #expect(reloaded.entries.map(\.output) == ["two", "one"])
        #expect(reloaded.search("ONE").map(\.input) == ["first"])
        let permissions = try? FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        #expect(permissions == 0o600)
    }

    @Test func keepsAtMostTheLimit() {
        let store = HistoryStore(fileURL: url, isEnabled: { true })
        for index in 0..<(HistoryStore.maxEntries + 5) {
            store.record(source: "Panel", input: "\(index)", output: "a", route: .onDevice)
        }
        #expect(store.entries.count == HistoryStore.maxEntries)
        #expect(store.entries.first?.input == "\(HistoryStore.maxEntries + 4)")
    }

    @Test func turningOffDeletesTheFile() {
        let flag = Flag(true)
        let store = HistoryStore(fileURL: url, isEnabled: { flag.on })
        store.record(source: "Panel", input: "q", output: "a", route: .onDevice)
        #expect(FileManager.default.fileExists(atPath: url.path))
        flag.on = false
        store.preferenceChanged()
        #expect(store.entries.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func clearDeletesEverything() {
        let store = HistoryStore(fileURL: url, isEnabled: { true })
        store.record(source: "Panel", input: "q", output: "a", route: .onDevice)
        store.clear()
        #expect(store.entries.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }
}

/// "Only on this Mac": in a build that has Private Cloud Compute, no flow creates a cloud conversation.
@MainActor
struct OnlyOnMacTests {
    let model = MockModelService()
    let preferences: Preferences = {
        let preferences = Preferences(defaults: makeTestDefaults())
        preferences.privateCloudInBuild = true
        preferences.onlyOnMac = true
        return preferences
    }()

    var cloudConversations: Int { model.conversations.filter { $0.route == .privateCloud }.count }

    func cloudAction() -> LampoAction {
        LampoAction(name: "Cloud", symbol: "cloud", promptTemplate: "Rewrite: {{selection}}", route: .privateCloud)
    }

    @Test func panelQuestionsAndThinkHarderStayOnTheMac() async {
        let vm = PanelViewModel(model: model, preferences: preferences, pasteboard: MockPasteboard())
        vm.query = "Explain this"
        vm.submit()
        await vm.generationTask?.value
        #expect(!vm.canThinkHarder)
        vm.thinkHarder()
        await vm.generationTask?.value
        vm.goDeeper()
        await vm.generationTask?.value
        #expect(cloudConversations == 0)
        #expect(!model.conversations.isEmpty)
    }

    @Test func cloudActionsRunOnTheMac() async throws {
        let runner = ActionRunner(model: model, preferences: preferences)
        let context = runner.templateContext(selection: "ciao", clipboard: nil, app: nil)
        let run = try await runner.start(cloudAction(), context: context)
        for try await _ in run.stream {}
        #expect(run.route == .onDevice)
        #expect(cloudConversations == 0)
    }

    @Test func lensThinkHarderIsBlocked() async {
        let runner = ActionRunner(model: model, preferences: preferences)
        let lens = LensViewModel(selection: SelectionContext(text: "ciao", app: .textEdit, anchor: nil, element: nil, source: .accessibility),
                                 actions: [cloudAction()], initialActionID: cloudAction().id,
                                 runner: runner, pasteboard: MockPasteboard(), routingPolicy: preferences.routingPolicy)
        lens.start()
        await lens.task?.value
        #expect(!lens.canThinkHarder)
        lens.thinkHarder()
        await lens.task?.value
        #expect(cloudConversations == 0)
    }

    @Test func draftsStayOnTheMac() async {
        let vm = PanelViewModel(model: model, preferences: preferences, pasteboard: MockPasteboard(),
                                calendarWriter: MockCalendarWriter())
        vm.startDraft(.event, from: "cena giovedì alle 20")
        await vm.draftTask?.value
        // Extraction is a separate on-device call; it never opens a conversation.
        #expect(model.conversations.isEmpty)
    }

    @Test func withTheSwitchOffThinkHarderUsesTheCloud() async {
        preferences.onlyOnMac = false
        let vm = PanelViewModel(model: model, preferences: preferences, pasteboard: MockPasteboard())
        vm.query = "Explain this"
        vm.submit()
        await vm.generationTask?.value
        #expect(vm.canThinkHarder)
        vm.thinkHarder()
        await vm.generationTask?.value
        #expect(cloudConversations == 1)
    }
}
