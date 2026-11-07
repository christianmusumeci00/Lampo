import Foundation
import Testing
@testable import Lampo

/// Dates are resolved in a fixed calendar (Rome) from Sunday 8 November 2026, 10:00.
struct WhenParserTests {
    let parser = WhenParser(now: TestDates.sundayMorning, calendar: TestDates.calendar, locale: Locale(identifier: "it_IT"))
    let d = TestDates.date

    @Test func weekdayAndTime() {
        let when = parser.parse("cena con Marco giovedì alle 20")
        #expect(when.day == d(2026, 11, 12, 0, 0))
        #expect(when.start == ClockTime(hour: 20))
    }

    @Test func relativeDays() {
        #expect(parser.parse("domani alle 9:30").day == d(2026, 11, 9, 0, 0))
        #expect(parser.parse("domani alle 9:30").start == ClockTime(hour: 9, minute: 30))
        #expect(parser.parse("dopodomani").day == d(2026, 11, 10, 0, 0))
        #expect(parser.parse("tomorrow at 3pm").start == ClockTime(hour: 15))
        #expect(parser.parse("tra 3 giorni").day == d(2026, 11, 11, 0, 0))
    }

    @Test func rangesAndDurations() {
        let range = parser.parse("riunione lunedì dalle 14 alle 16")
        #expect(range.day == d(2026, 11, 9, 0, 0))
        #expect(range.start == ClockTime(hour: 14))
        #expect(range.end == ClockTime(hour: 16))

        let english = parser.parse("call from 9:30 to 11")
        #expect(english.start == ClockTime(hour: 9, minute: 30))
        #expect(english.end == ClockTime(hour: 11))

        #expect(parser.parse("meeting tomorrow at 3pm for 90 minutes").durationMinutes == 90)
        #expect(parser.parse("corsa per un'ora e mezza").durationMinutes == 90)
        // Without "per"/"for" it isn't a duration ("tra un'ora" is when, not how long).
        #expect(parser.parse("tra un'ora").durationMinutes == nil)
    }

    @Test func hoursWithoutDayPartAreAfternoonUpToSeven() {
        #expect(parser.parse("alle 3").start == ClockTime(hour: 15))
        #expect(parser.parse("alle 8").start == ClockTime(hour: 8))
        #expect(parser.parse("alle 8 di sera").start == ClockTime(hour: 20))
        #expect(parser.parse("alle 20 e mezza").start == ClockTime(hour: 20, minute: 30))
        #expect(parser.parse("alle 9 e un quarto di mattina").start == ClockTime(hour: 9, minute: 15))
        #expect(parser.parse("cena alle 20.30 venerdì").start == ClockTime(hour: 20, minute: 30))
        #expect(parser.parse("cena alle 20.30 venerdì").day == d(2026, 11, 13, 0, 0))
    }

    @Test func namedAndNumericDates() {
        #expect(parser.parse("12 dicembre compleanno di Luca").day == d(2026, 12, 12, 0, 0))
        // Already past this year: next year.
        #expect(parser.parse("3 marzo").day == d(2027, 3, 3, 0, 0))
        #expect(parser.parse("December 24th").day == d(2026, 12, 24, 0, 0))
        // Day first in Italy.
        #expect(parser.parse("il 12/3").day == d(2027, 3, 12, 0, 0))
        #expect(parser.parse("2027-01-15").day == d(2027, 1, 15, 0, 0))
    }

    @Test func sameWeekdayMeansNextWeekOnceTheTimeHasPassed() {
        let sunday = WhenParser(now: TestDates.sundayMorning, calendar: TestDates.calendar)
        #expect(sunday.parse("domenica alle 18").day == d(2026, 11, 8, 0, 0))
        #expect(sunday.parse("domenica alle 9").day == d(2026, 11, 15, 0, 0))
    }

    @Test func dayPartsAndOccasions() {
        let tonight = parser.parse("aperitivo stasera")
        #expect(tonight.day == d(2026, 11, 8, 0, 0))
        #expect(tonight.dayPart == .evening)
        #expect(parser.parse("pranzo con Anna").occasionTime == ClockTime(hour: 13))
    }
}

struct DraftBuilderTests {
    let parser = WhenParser(now: TestDates.sundayMorning, calendar: TestDates.calendar, locale: Locale(identifier: "it_IT"))
    let d = TestDates.date

    /// The M4 acceptance case.
    @Test func dinnerWithMarcoOnThursday() {
        let details = ExtractedDetails(title: "Cena con Marco", dayText: "giovedì", startTime: "20:00", location: "")
        let event = DraftBuilder.event(from: "cena con Marco giovedì alle 20", details: details, parser: parser)
        #expect(event.title == "Cena con Marco")
        #expect(event.start == d(2026, 11, 12, 20, 0))
        #expect(event.end == d(2026, 11, 12, 21, 0))
        #expect(!event.isAllDay)
        #expect(event.location.isEmpty)
    }

    @Test func worksWithoutTheModel() {
        let event = DraftBuilder.event(from: "cena con Marco giovedì alle 20", details: ExtractedDetails(), parser: parser)
        #expect(event.start == d(2026, 11, 12, 20, 0))
        #expect(event.title.hasPrefix("Cena con Marco"))
    }

    @Test func modelDayIsUsedWhenTheTextHasNone() {
        let details = ExtractedDetails(title: "Cena", dayText: "domani", startTime: "", location: "")
        let event = DraftBuilder.event(from: "cena da organizzare per il giorno dopo", details: details, parser: parser)
        // "cena" gives the usual 20:00; the day comes from the model's words.
        #expect(event.start == d(2026, 11, 9, 20, 0))
    }

    @Test func modelTimeNeedsAHintInTheText() {
        let details = ExtractedDetails(title: "Riunione", dayText: "giovedì", startTime: "10:00", location: "")
        let event = DraftBuilder.event(from: "riunione giovedì", details: details, parser: parser)
        #expect(event.isAllDay)
        #expect(event.start == d(2026, 11, 12, 0, 0))
    }

    @Test func rangeSetsTheEnd() {
        let event = DraftBuilder.event(from: "riunione lunedì dalle 14 alle 16", details: ExtractedDetails(), parser: parser)
        #expect(event.start == d(2026, 11, 9, 14, 0))
        #expect(event.end == d(2026, 11, 9, 16, 0))
    }

    @Test func durationSetsTheEnd() {
        let event = DraftBuilder.event(from: "meeting tomorrow at 3pm for 90 minutes", details: ExtractedDetails(), parser: parser)
        #expect(event.start == d(2026, 11, 9, 15, 0))
        #expect(event.end == d(2026, 11, 9, 16, 30))
    }

    @Test func noDayMeansTodayOrTomorrow() {
        // 10:00 now: lunch at 13 is still today, breakfast at 8:30 is tomorrow.
        let lunch = DraftBuilder.event(from: "pranzo con Anna", details: ExtractedDetails(), parser: parser)
        #expect(lunch.start == d(2026, 11, 8, 13, 0))
        let breakfast = DraftBuilder.event(from: "colazione con Anna", details: ExtractedDetails(), parser: parser)
        #expect(breakfast.start == d(2026, 11, 9, 8, 30))
    }

    @Test func locationMustBeInTheText() {
        #expect(DraftBuilder.location("da Mario", text: "Cena da Mario giovedì") == "da Mario")
        #expect(DraftBuilder.location("Roma", text: "Cena da Mario giovedì").isEmpty)
        #expect(DraftBuilder.location("none", text: "none of this").isEmpty)
    }

    @Test func reminderWithDueTime() {
        let details = ExtractedDetails(title: "Ricordami di chiamare Anna", dayText: "domani", startTime: "10:00", location: "")
        let reminder = DraftBuilder.reminder(from: "ricordami di chiamare Anna domani alle 10", details: details, parser: parser)
        #expect(reminder.title == "Chiamare Anna")
        #expect(reminder.hasDueDate)
        #expect(reminder.hasDueTime)
        #expect(reminder.due == d(2026, 11, 9, 10, 0))
    }

    @Test func loneVerbTitleUsesTheText() {
        let details = ExtractedDetails(title: "Chiamare", dayText: "domani", startTime: "10:00", location: "")
        let reminder = DraftBuilder.reminder(from: "ricordami di chiamare Anna domani alle 10 per il preventivo",
                                             details: details, parser: parser)
        #expect(reminder.title == "Chiamare Anna per il preventivo")
        #expect(DraftBuilder.withoutWhen("call Bob next Tuesday at 3pm") == "call Bob")
    }

    @Test func reminderWithoutDate() {
        let details = ExtractedDetails(title: "comprare il latte", dayText: "", startTime: "", location: "")
        let reminder = DraftBuilder.reminder(from: "comprare il latte", details: details, parser: parser)
        #expect(reminder.title == "Comprare il latte")
        #expect(!reminder.hasDueDate)
        #expect(!reminder.hasDueTime)
    }

    @Test func reminderDayWithoutTime() {
        let reminder = DraftBuilder.reminder(from: "pagare la bolletta venerdì", details: ExtractedDetails(), parser: parser)
        #expect(reminder.hasDueDate)
        #expect(!reminder.hasDueTime)
        #expect(reminder.due == d(2026, 11, 13, 0, 0))
    }

    @Test func movingTheStartKeepsTheDuration() {
        var event = CalendarEventDraft(title: "A", start: d(2026, 11, 9, 14, 0), end: d(2026, 11, 9, 16, 0),
                                       isAllDay: false, location: "", notes: "")
        event.moveStart(to: d(2026, 11, 10, 9, 0))
        #expect(event.end == d(2026, 11, 10, 11, 0))
    }

    @Test func longTextsGoInTheNotes() {
        let email = Array(repeating: "parola", count: 30).joined(separator: " ") + " giovedì alle 20"
        let event = DraftBuilder.event(from: email, details: ExtractedDetails(title: "Riunione"), parser: parser)
        #expect(event.notes == email)
        let short = DraftBuilder.event(from: "cena giovedì", details: ExtractedDetails(), parser: parser)
        #expect(short.notes.isEmpty)
    }
}

/// The confirmation card: nothing is written until the user confirms.
@MainActor
struct PanelDraftTests {
    let model = MockModelService()
    let writer = MockCalendarWriter()
    let preferences = Preferences(defaults: makeTestDefaults())

    func makeViewModel() -> PanelViewModel {
        let vm = PanelViewModel(model: model, preferences: preferences, pasteboard: MockPasteboard(),
                                calendarWriter: writer, now: { TestDates.sundayMorning })
        vm.userCalendar = TestDates.calendar
        return vm
    }

    func readyDraft(_ kind: DraftKind = .event, text: String = "cena con Marco giovedì alle 20") async -> PanelViewModel {
        model.extracted = ExtractedDetails(title: "Cena con Marco", dayText: "giovedì", startTime: "20:00", location: "")
        let vm = makeViewModel()
        vm.startDraft(kind, from: text)
        await vm.draftTask?.value
        return vm
    }

    @Test func draftIsReadyButNotSaved() async {
        let vm = await readyDraft()
        #expect(vm.draft?.phase == .editing)
        #expect(vm.draft?.event.start == TestDates.date(2026, 11, 12, 20, 0))
        #expect(model.extractions.map(\.kind) == [.event])
        #expect(writer.savedEvents.isEmpty)
        #expect(writer.accessRequests.isEmpty)
    }

    @Test func extractionFailureFallsBackToTheParser() async {
        model.extractionFailure = ModelError.refusal
        let vm = makeViewModel()
        vm.startDraft(.event, from: "cena con Marco giovedì alle 20")
        await vm.draftTask?.value
        #expect(vm.draft?.phase == .editing)
        #expect(vm.draft?.event.start == TestDates.date(2026, 11, 12, 20, 0))
    }

    @Test func confirmSavesTheEditedDraft() async {
        let vm = await readyDraft()
        vm.draft?.event.title = "Cena con Marco e Giulia"
        vm.confirmDraft()
        await vm.draftTask?.value
        #expect(vm.draft?.phase == .saved)
        #expect(writer.savedEvents.map(\.title) == ["Cena con Marco e Giulia"])
    }

    @Test func emptyTitleCantBeConfirmed() async {
        let vm = await readyDraft()
        vm.draft?.event.title = "  "
        #expect(vm.draft?.canConfirm == false)
        vm.confirmDraft()
        await vm.draftTask?.value
        #expect(writer.savedEvents.isEmpty)
    }

    @Test func deniedAccessOffersSettings() async {
        writer.accessValue = .denied
        let vm = await readyDraft()
        vm.confirmDraft()
        await vm.draftTask?.value
        #expect(vm.draft?.needsSettings == true)
        if case .failed = vm.draft?.phase {} else { Issue.record("expected a failure") }
        #expect(writer.savedEvents.isEmpty)
        vm.openDraftSettings()
        #expect(writer.openedSettings == [.event])
    }

    @Test func firstConfirmAsksForAccess() async {
        writer.accessValue = .notDetermined
        let vm = await readyDraft(.reminder, text: "ricordami di chiamare Anna domani alle 10")
        vm.confirmDraft()
        await vm.draftTask?.value
        #expect(writer.accessRequests == [.reminder])
        #expect(writer.savedReminders.count == 1)
        #expect(vm.draft?.phase == .saved)
    }

    @Test func refusedPromptSavesNothing() async {
        writer.accessValue = .notDetermined
        writer.grantsOnRequest = false
        let vm = await readyDraft()
        vm.confirmDraft()
        await vm.draftTask?.value
        #expect(writer.savedEvents.isEmpty)
        #expect(vm.draft?.needsSettings == true)
    }

    @Test func saveFailureCanBeRetried() async {
        writer.saveFailure = .saveFailed
        let vm = await readyDraft()
        vm.confirmDraft()
        await vm.draftTask?.value
        #expect(vm.draft?.canConfirm == true)
        writer.saveFailure = nil
        vm.confirmDraft()
        await vm.draftTask?.value
        #expect(writer.savedEvents.count == 1)
    }

    @Test func discardWritesNothing() async {
        let vm = await readyDraft()
        vm.discardDraft()
        #expect(vm.draft == nil)
        #expect(writer.savedEvents.isEmpty)
    }

    @Test func draftInputModeTurnsTheQuestionIntoADraft() async {
        let vm = makeViewModel()
        vm.enterDraftInput(.event)
        vm.query = "cena con Marco giovedì alle 20"
        vm.submit()
        await vm.draftTask?.value
        #expect(vm.draft?.kind == .event)
        #expect(vm.turns.isEmpty)
        #expect(model.conversations.isEmpty)
        #expect(writer.savedEvents.isEmpty)
    }
}
