import Foundation
import Testing
@testable import Lampo

struct ListSplitterTests {
    @Test func addsBackWhatTheModelDropped() {
        let source = "latte, chiamare Luca domani, bolletta venerdì"
        let items = ListSplitter.reconcile(source: source, items: ["chiamare Luca domani", "bolletta venerdì"])
        #expect(items == ["latte", "chiamare Luca domani", "bolletta venerdì"])
    }

    @Test func oneEventStaysOne() {
        let source = "cena con Marco e Luca giovedì alle 20 da Gino"
        #expect(ListSplitter.reconcile(source: source, items: [source]) == [source])
        // The model split one event in pieces: the day, time and place go back with it.
        let comma = "cena con Marco, giovedì alle 20 da Gino"
        #expect(ListSplitter.reconcile(source: comma, items: ["cena con Marco", "giovedì alle 20", "da Gino"]) == [comma])
    }

    @Test func keepsTheTextsOrderAndDropsInventions() {
        let source = "Call Anna tomorrow at 10; send the invoice Friday; book flights"
        let items = ListSplitter.reconcile(source: source, items: ["book flights", "Call Anna tomorrow at 10",
                                                                   "Buy a present", "send the invoice Friday"])
        #expect(items == ["Call Anna tomorrow at 10", "send the invoice Friday", "book flights"])
    }

    @Test func finerItemsWinOverlaps() {
        let source = "riunione lunedì alle 10, dentista giovedì alle 15 e palestra sabato mattina"
        let overlapping = ListSplitter.reconcile(source: source, items: [
            "riunione lunedì alle 10", "dentista giovedì alle 15", "dentista giovedì alle 15 e palestra sabato mattina",
            "palestra sabato mattina"])
        #expect(overlapping == ["riunione lunedì alle 10", "dentista giovedì alle 15", "palestra sabato mattina"])
        // The model skipped "palestra": it comes back from the text.
        let skipped = ListSplitter.reconcile(source: source, items: [
            "riunione lunedì alle 10", "dentista giovedì alle 15 e palestra sabato mattina", "dentista giovedì alle 15"])
        #expect(skipped == ["riunione lunedì alle 10", "dentista giovedì alle 15", "palestra sabato mattina"])
    }

    @Test func aGreetingIsntAnItem() {
        let source = "Ciao, ricordami di comprare il latte domani"
        #expect(ListSplitter.reconcile(source: source, items: ["ricordami di comprare il latte domani"]) == [source])
    }

    @Test func bulletsAndNumbersAreStripped() {
        let source = "- pane\n- latte\n2) chiamare la nonna"
        #expect(ListSplitter.reconcile(source: source, items: ["- pane", "latte"]) == ["pane", "latte", "chiamare la nonna"])
        #expect(ListSplitter.fallback(source) == ["pane", "latte", "chiamare la nonna"])
        // Without the model, commas aren't trusted.
        #expect(ListSplitter.fallback("pane, latte") == ["pane, latte"])
    }

    @Test func onlyShortTextsWithSeparatorsAreLists() {
        #expect(ListSplitter.mayBeList("latte, pane"))
        #expect(ListSplitter.mayBeList("comprare pane e latte"))
        #expect(!ListSplitter.mayBeList("cena con Marco giovedì alle 20"))
        #expect(!ListSplitter.mayBeList(Array(repeating: "parola,", count: 70).joined(separator: " ")))
    }

    @Test func fragments() {
        #expect(ListSplitter.isFragment("giovedì alle 20"))
        #expect(ListSplitter.isFragment("da Gino"))
        #expect(!ListSplitter.isFragment("latte"))
        #expect(!ListSplitter.isFragment("chiamare Luca domani"))
    }
}

@MainActor
struct DraftListTests {
    let model = MockModelService()
    let writer = MockCalendarWriter()
    let preferences = Preferences(defaults: makeTestDefaults())

    func makeViewModel() -> PanelViewModel {
        let vm = PanelViewModel(model: model, preferences: preferences, pasteboard: MockPasteboard(),
                                calendarWriter: writer, now: { TestDates.sundayMorning })
        vm.userCalendar = TestDates.calendar
        return vm
    }

    func listDraft(_ text: String = "latte, chiamare Luca domani, bolletta venerdì") async -> PanelViewModel {
        let vm = makeViewModel()
        vm.startDraft(.reminder, from: text)
        await vm.draftTask?.value
        return vm
    }

    @Test func aListBecomesOneReminderEach() async {
        let vm = await listDraft()
        let card = vm.draft
        #expect(card?.phase == .editing)
        #expect(card?.isList == true)
        #expect(card?.items.map(\.reminder.title) == ["Latte", "Chiamare Luca", "Bolletta"])
        #expect(card?.items[0].reminder.hasDueDate == false)
        #expect(card?.items[1].reminder.due == TestDates.date(2026, 11, 9, 0, 0))
        #expect(card?.items[2].reminder.due == TestDates.date(2026, 11, 13, 0, 0))
        // One model call (the split): each item is dated by the parser.
        #expect(model.extractCalls == ["split"])
        #expect(model.extractions.isEmpty)
    }

    @Test func eventsFromAList() async {
        let vm = makeViewModel()
        vm.startDraft(.event, from: "riunione lunedì alle 10, dentista giovedì alle 15")
        await vm.draftTask?.value
        #expect(vm.draft?.items.map(\.event.title) == ["Riunione", "Dentista"])
        #expect(vm.draft?.items.map(\.event.start) == [TestDates.date(2026, 11, 9, 10, 0), TestDates.date(2026, 11, 12, 15, 0)])
    }

    @Test func confirmAddsTheTickedItems() async {
        let vm = await listDraft()
        vm.draft?.items[0].isIncluded = false
        vm.confirmDraft()
        await vm.draftTask?.value
        #expect(writer.savedReminders.map(\.title) == ["Chiamare Luca", "Bolletta"])
        #expect(vm.draft?.phase == .saved)
        #expect(vm.draft?.savedCount == 2)
        #expect(PanelViewModel.savedMessage(.reminder, count: 2).contains("2"))
    }

    @Test func nothingTickedCantBeConfirmed() async {
        let vm = await listDraft()
        for index in vm.draft!.items.indices { vm.draft?.items[index].isIncluded = false }
        #expect(vm.draft?.canConfirm == false)
    }

    @Test func aRetryAfterAPartialFailureDoesntAddTwice() async {
        writer.failAfter = 1
        let vm = await listDraft()
        vm.confirmDraft()
        await vm.draftTask?.value
        if case .failed = vm.draft?.phase {} else { Issue.record("expected a failure") }
        #expect(vm.draft?.items.count == 2)
        #expect(vm.draft?.savedCount == 1)

        writer.failAfter = nil
        vm.confirmDraft()
        await vm.draftTask?.value
        #expect(writer.savedReminders.map(\.title) == ["Latte", "Chiamare Luca", "Bolletta"])
        #expect(vm.draft?.savedCount == 3)
    }

    @Test func withoutTheModelOnlyLinesSplit() async {
        model.extractionFailure = ModelError.unavailable(.appleIntelligenceNotEnabled)
        let lines = await listDraft("pane\nchiamare Luca domani")
        #expect(lines.draft?.items.count == 2)
        let commas = await listDraft("latte, chiamare Luca domani")
        #expect(commas.draft?.isList == false)
        #expect(commas.draft?.phase == .editing)
    }

    @Test func aSingleItemKeepsTheDetailedExtraction() async {
        model.splitResult = ["cena con Marco e Luca giovedì alle 20"]
        model.extracted = ExtractedDetails(title: "Cena con Marco e Luca", dayText: "giovedì", startTime: "20:00")
        let vm = makeViewModel()
        vm.startDraft(.event, from: "cena con Marco e Luca giovedì alle 20")
        await vm.draftTask?.value
        #expect(vm.draft?.isList == false)
        #expect(vm.draft?.event.title == "Cena con Marco e Luca")
        #expect(model.extractCalls == ["split"])
        #expect(model.extractions.count == 1)
    }
}

struct ExtractShapeTests {
    let signature = """
        Giulia Bianchi
        Responsabile Marketing · Acme S.r.l.
        Tel. +39 02 1234 5678 · giulia.bianchi@acme.it
        """

    @Test func guessesTheKindFromTheText() {
        #expect(ExtractKind.guess(for: signature) == .contact)
        #expect(ExtractKind.guess(for: "Mario Rossi - 12 - Milano\nAnna Verdi - 34 - Roma\nLuca Neri - 27 - Torino") == .table)
        #expect(ExtractKind.guess(for: "Puoi mandarmi il preventivo entro venerdì? E prenota la sala.") == .todos)
    }

    @Test func contactKeepsOnlyWhatTheTextSays() {
        let raw = ContactDraft(givenName: "Giulia", familyName: "Bianchi", organization: "Acme S.r.l.",
                               jobTitle: "CEO", phones: ["+39 02 1234 5678", "+39 333 0000000"],
                               emails: ["giulia.bianchi@acme.it", "info@acme.it"], address: "", website: "N/A")
        let checked = raw.checked(against: signature)
        #expect(checked.jobTitle == "")
        #expect(checked.phones == ["+39 02 1234 5678"])
        #expect(checked.emails == ["giulia.bianchi@acme.it"])
        #expect(checked.website == "")
        #expect(checked.displayName == "Giulia Bianchi")
    }

    @Test func aRepeatedFirstNameIsNotALastName() {
        let text = "Marco prepara il preventivo entro venerdì."
        let checked = ContactDraft(givenName: "Marco", familyName: "Marco").checked(against: text)
        #expect(checked.givenName == "Marco")
        #expect(checked.familyName == "")
        // A real "Marco Marco" stays.
        let real = ContactDraft(givenName: "Marco", familyName: "Marco").checked(against: "Firmato: Marco Marco")
        #expect(real.familyName == "Marco")
    }

    @Test func contactWithoutTheModel() {
        let detected = ContactDraft.detected(in: signature)
        #expect(detected.phones.count == 1)
        #expect(detected.emails == ["giulia.bianchi@acme.it"])
        #expect(detected.givenName.isEmpty)
    }

    @Test func vCardForContacts() throws {
        let contact = ContactDraft(givenName: "Giulia", familyName: "Bianchi", organization: "Acme",
                                   phones: ["+39 02 1234 5678"], emails: ["giulia@acme.it"])
        let card = String(decoding: try contact.vCard(), as: UTF8.self)
        #expect(card.contains("BEGIN:VCARD"))
        #expect(card.contains("Bianchi;Giulia"))
        #expect(card.contains("+39 02 1234 5678"))
        #expect(card.contains("giulia@acme.it"))
    }

    @Test func tableCopiesAsCellsOrMarkdown() {
        let table = ExtractedTable(columns: ["Nome", "Età"], rows: [["Mario", "12", "extra"], ["Anna"]]).normalized()
        #expect(table.columns == ["Nome", "Età", ""])
        #expect(table.rows == [["Mario", "12", "extra"], ["Anna", "", ""]])
        #expect(table.tabSeparated == "Nome\tEtà\t\nMario\t12\textra\nAnna\t\t")
        #expect(table.markdown.hasPrefix("| Nome | Età |  |\n| --- | --- | --- |"))
    }

    @Test func tableWithoutTheModel() {
        let markdown = "| a | b |\n| --- | --- |\n| 1 | 2 |\n| 3 | 4 |"
        #expect(TableShape.parse(markdown).rows == [["a", "b"], ["1", "2"], ["3", "4"]])
        #expect(TableShape.parse("una riga\ne un'altra").isEmpty)
    }
}

@MainActor
struct ExtractPanelTests {
    let model = MockModelService()
    let pasteboard = MockPasteboard()
    let preferences = Preferences(defaults: makeTestDefaults())

    func makeViewModel() -> PanelViewModel {
        let vm = PanelViewModel(model: model, preferences: preferences, pasteboard: pasteboard,
                                calendarWriter: MockCalendarWriter(), now: { TestDates.sundayMorning })
        vm.userCalendar = TestDates.calendar
        return vm
    }

    @Test func contactIsHandedToContacts() async {
        model.contact = ContactDraft(givenName: "Giulia", familyName: "Bianchi", emails: ["giulia@acme.it"])
        let vm = makeViewModel()
        var opened: [ContactDraft] = []
        var closed = false
        vm.openContact = { opened.append($0); return true }
        vm.onRequestClose = { closed = true }
        vm.startExtraction(from: "Giulia Bianchi — giulia@acme.it")
        await vm.draftTask?.value
        #expect(vm.extraction?.kind == .contact)
        #expect(vm.extraction?.phase == .ready)
        vm.saveContact()
        #expect(opened.map(\.displayName) == ["Giulia Bianchi"])
        #expect(closed)
    }

    @Test func switchingToToDosShowsReminders() async {
        model.contact = ContactDraft()
        model.tasks = ["mandare il preventivo entro venerdì", "chiamare Paolo", "chiamare Paolo"]
        let vm = makeViewModel()
        vm.startExtraction(from: "Giulia: giulia@acme.it. Mandami il preventivo entro venerdì e chiama Paolo.")
        await vm.draftTask?.value
        #expect(vm.extraction?.phase == .failed(PanelViewModel.nothingFound(.contact)))

        vm.switchExtraction(to: .todos)
        await vm.draftTask?.value
        #expect(vm.extraction?.kind == .todos)
        #expect(vm.draft?.kind == .reminder)
        #expect(vm.draft?.items.map(\.reminder.title) == ["Mandare il preventivo", "Chiamare Paolo"])
        #expect(vm.draft?.items.first?.reminder.due == TestDates.date(2026, 11, 13, 0, 0))
    }

    @Test func tableIsCopiedForNumbers() async {
        model.table = ExtractedTable(columns: ["Nome", "Città"], rows: [[GeneratedNames.mario, "Milano"]])
        let vm = makeViewModel()
        vm.startExtraction(from: "Mario Rossi abita a Milano", kind: .table)
        await vm.draftTask?.value
        vm.copyTable()
        #expect(pasteboard.contents == "Nome\tCittà\nMario Rossi\tMilano")
        vm.copyTable(asMarkdown: true)
        #expect(pasteboard.contents?.hasPrefix("| Nome | Città |") == true)
    }

    @Test func withoutTheModelSimpleRulesHelp() async {
        model.extractionFailure = ModelError.unavailable(.appleIntelligenceNotEnabled)
        let vm = makeViewModel()
        vm.startExtraction(from: "Scrivimi a giulia@acme.it o chiama il 02 1234 5678")
        await vm.draftTask?.value
        #expect(vm.extraction?.kind == .contact)
        #expect(vm.extraction?.isFallback == true)
        #expect(vm.extraction?.contact.emails == ["giulia@acme.it"])
    }

    @Test func extractActionIsStructured() {
        let extract = BuiltInActions.all.first { $0.id == BuiltInActions.extractID }
        #expect(extract?.output == .extract)
        #expect(extract?.output.isStructured == true)
        #expect(extract?.output.showsInLens == false)
    }

    private enum GeneratedNames {
        static let mario = "Mario Rossi"
    }
}

@MainActor
struct ReplyTests {
    let model = MockModelService()
    let preferences = Preferences(defaults: makeTestDefaults())
    var reply: LampoAction { BuiltInActions.all.first { $0.id == BuiltInActions.replyID }! }

    @Test func replyIsWrittenInTheMessagesLanguageAndInsertedAtTheCursor() async {
        let runner = ActionRunner(model: model, preferences: preferences, translator: MockTranslator())
        let message = "Hi Christian, could we move our call to Thursday afternoon? Let me know. Thanks, Sarah"
        let selection = SelectionContext(text: message, app: .textEdit, anchor: nil, element: nil, source: .accessibility)
        let context = runner.templateContext(selection: message, clipboard: nil, app: "Mail")
        let prompt = runner.prompt(for: reply, context: context)
        #expect(prompt.contains("which is in English"))
        #expect(prompt.contains(message))

        let vm = PanelViewModel(model: model, preferences: preferences, pasteboard: MockPasteboard())
        var inserted: [(String, SelectionContext?)] = []
        vm.onInsert = { inserted.append(($0, $1)) }
        vm.runAction(reply, prompt: prompt, contextItems: [.selection(selection)])
        await vm.generationTask?.value
        #expect(vm.replyLanguage == "English")
        vm.insertCurrentAnswer()
        #expect(inserted.count == 1)
        #expect(inserted.first?.1 == nil)

        // "più breve": the reply is rewritten, still in English.
        vm.query = "più breve"
        vm.submit()
        await vm.generationTask?.value
        let followUp = model.conversations.last?.prompts.last ?? ""
        #expect(followUp.contains("“più breve”"))
        #expect(followUp.contains("in English"))
        #expect(vm.currentTurn?.question == "più breve")
    }

    @Test func otherPanelActionsStillReplaceTheSelection() async {
        let explain = BuiltInActions.all.first { $0.id == BuiltInActions.explainID }!
        let selection = SelectionContext(text: "entropia", app: .textEdit, anchor: nil, element: nil, source: .accessibility)
        let vm = PanelViewModel(model: model, preferences: preferences, pasteboard: MockPasteboard())
        vm.runAction(explain, prompt: "Explain", contextItems: [.selection(selection)])
        await vm.generationTask?.value
        #expect(vm.activeSelection?.text == "entropia")
        #expect(vm.replyLanguage == nil)
    }
}

@MainActor
struct ScreenTextTests {
    @Test func linesAreReadTopToBottomAndLeftToRight() {
        let lines = [
            ScreenText.Line(text: "second", x: 0.1, y: 0.5, height: 0.02),
            ScreenText.Line(text: "right", x: 0.6, y: 0.901, height: 0.02),
            ScreenText.Line(text: "left", x: 0.1, y: 0.9, height: 0.02),
        ]
        #expect(ScreenText.layout(lines) == "left   right\nsecond")
    }

    @Test func recognizedTextGoesWithTheScreenshot() async {
        let model = MockModelService()
        let capture = MockScreenCapture()
        capture.text = "error: cannot find 'foo' in scope"
        let vm = PanelViewModel(model: model, preferences: Preferences(defaults: makeTestDefaults()),
                                pasteboard: MockPasteboard(), screenCapture: capture)
        vm.toggleWindow(from: .terminal, permitted: true)
        await waitUntil { vm.hasWindowContext }
        vm.query = "what does it mean?"
        vm.submit()
        await vm.generationTask?.value
        let prompt = model.conversations.first?.prompts.first ?? ""
        #expect(prompt.contains("<screen>\nerror: cannot find 'foo' in scope\n</screen>"))
        #expect(model.conversations.first?.imageCounts == [1])
    }

    @Test func longScreenTextIsCut() async {
        let model = MockModelService()
        model.contextSizeValue = 2500
        let capture = MockScreenCapture()
        capture.text = (1...3000).map { "w\($0)" }.joined(separator: " ")
        let vm = PanelViewModel(model: model, preferences: Preferences(defaults: makeTestDefaults()),
                                pasteboard: MockPasteboard(), screenCapture: capture)
        vm.toggleWindow(from: .terminal, permitted: true)
        await waitUntil { vm.hasWindowContext }
        vm.query = "riassumi"
        vm.submit()
        await vm.generationTask?.value
        let prompt = model.conversations.first?.prompts.first ?? ""
        #expect(prompt.contains("[…]"))
        #expect(prompt.contains("w1 "))
        #expect(!prompt.contains("w1500 "))
        #expect(vm.currentTurn?.wasTruncated == true)
    }
}
