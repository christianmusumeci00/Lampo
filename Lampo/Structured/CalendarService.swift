import AppKit
import EventKit

enum CalendarAccess: Equatable, Sendable {
    case granted
    case notDetermined
    case denied
}

enum CalendarWriteError: LocalizedError, Equatable {
    case accessDenied(DraftKind)
    case noDefaultList(DraftKind)
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .accessDenied(.event):
            return String(localized: "Lampo can't add events: allow it in System Settings › Privacy & Security › Calendars.")
        case .accessDenied(.reminder):
            return String(localized: "Lampo can't add reminders: allow it in System Settings › Privacy & Security › Reminders.")
        case .noDefaultList(.event):
            return String(localized: "There's no default calendar. Choose one in Calendar › Settings.")
        case .noDefaultList(.reminder):
            return String(localized: "There's no default reminders list. Choose one in Reminders › Settings.")
        case .saveFailed:
            return String(localized: "Couldn't save. Try again.")
        }
    }
}

/// Writes confirmed drafts to Calendar and Reminders. Mocked in tests.
@MainActor
protocol CalendarWriting: AnyObject {
    func access(for kind: DraftKind) -> CalendarAccess
    /// Shows the system prompt the first time.
    func requestAccess(for kind: DraftKind) async -> Bool
    func save(_ draft: CalendarEventDraft) throws
    func save(_ draft: ReminderDraft) throws
    func openSettings(for kind: DraftKind)
    /// Opens Calendar at the event's day, or Reminders.
    func openApp(for kind: DraftKind, at date: Date?)
}

/// EventKit implementation. Events use **write-only** access: Lampo can add an event to the
/// default calendar but can't read the user's calendars. Reminders have no write-only level,
/// so they need full access.
@MainActor
final class CalendarService: CalendarWriting {
    private let store = EKEventStore()

    func access(for kind: DraftKind) -> CalendarAccess {
        switch EKEventStore.authorizationStatus(for: kind == .event ? .event : .reminder) {
        case .fullAccess, .writeOnly: return .granted
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }

    func requestAccess(for kind: DraftKind) async -> Bool {
        do {
            switch kind {
            case .event: return try await store.requestWriteOnlyAccessToEvents()
            case .reminder: return try await store.requestFullAccessToReminders()
            }
        } catch {
            Log.output.error("calendar access request failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    func save(_ draft: CalendarEventDraft) throws {
        guard let calendar = store.defaultCalendarForNewEvents else { throw CalendarWriteError.noDefaultList(.event) }
        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        event.title = draft.title
        event.isAllDay = draft.isAllDay
        event.startDate = draft.start
        event.endDate = draft.isAllDay ? draft.start : max(draft.end, draft.start)
        event.location = draft.location.isEmpty ? nil : draft.location
        event.notes = draft.notes.isEmpty ? nil : draft.notes
        do {
            try store.save(event, span: .thisEvent, commit: true)
            Log.output.info("event saved")
        } catch {
            Log.output.error("event save failed: \(error.localizedDescription, privacy: .public)")
            throw CalendarWriteError.saveFailed
        }
    }

    func save(_ draft: ReminderDraft) throws {
        guard let list = store.defaultCalendarForNewReminders() else { throw CalendarWriteError.noDefaultList(.reminder) }
        let reminder = EKReminder(eventStore: store)
        reminder.calendar = list
        reminder.title = draft.title
        reminder.notes = draft.notes.isEmpty ? nil : draft.notes
        if draft.hasDueDate {
            let units: Set<Calendar.Component> = draft.hasDueTime
                ? [.year, .month, .day, .hour, .minute] : [.year, .month, .day]
            reminder.dueDateComponents = Calendar.current.dateComponents(units, from: draft.due)
            if draft.hasDueTime { reminder.addAlarm(EKAlarm(absoluteDate: draft.due)) }
        }
        do {
            try store.save(reminder, commit: true)
            Log.output.info("reminder saved")
        } catch {
            Log.output.error("reminder save failed: \(error.localizedDescription, privacy: .public)")
            throw CalendarWriteError.saveFailed
        }
    }

    func openSettings(for kind: DraftKind) {
        let pane = kind == .event ? "Privacy_Calendars" : "Privacy_Reminders"
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }

    func openApp(for kind: DraftKind, at date: Date?) {
        switch kind {
        case .event:
            let interval = (date ?? .now).timeIntervalSinceReferenceDate
            if let url = URL(string: "calshow:\(interval)") { NSWorkspace.shared.open(url) }
        case .reminder:
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.reminders") {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            }
        }
    }
}
