import Foundation

/// What a structured action creates.
enum DraftKind: String, Codable, Sendable {
    case event
    case reminder
}

/// Words the model pulls out of a sentence. Dates and times are resolved by `WhenParser`,
/// so these stay plain strings (FoundationModels can't generate `Date` either).
struct ExtractedDetails: Equatable, Sendable {
    var title = ""
    /// The words that name the day, copied from the text ("giovedì", "next Tuesday").
    var dayText = ""
    /// "HH:mm" or empty.
    var startTime = ""
    var location = ""
}

/// An editable calendar event, shown for confirmation before anything is written.
struct CalendarEventDraft: Equatable, Sendable {
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
    var location: String
    var notes: String

    /// Moves the start and keeps the duration.
    mutating func moveStart(to date: Date) {
        let duration = end.timeIntervalSince(start)
        start = date
        end = date.addingTimeInterval(max(duration, 0))
    }
}

/// An editable reminder.
struct ReminderDraft: Equatable, Sendable {
    var title: String
    var hasDueDate: Bool
    var due: Date
    var hasDueTime: Bool
    var notes: String
}

/// Builds drafts from the original text and the model's extraction.
///
/// Priority for the start time: an explicit time in the text (parsed here) → the model's time,
/// only when the text hints at a time of day → the usual time of a meal ("cena" → 20:00) →
/// the part of the day ("stasera" → 19:00) → all day.
enum DraftBuilder {
    static let defaultDuration: TimeInterval = 60 * 60
    /// Longer texts (an email about a meeting) are kept in the notes.
    static let notesWordThreshold = 25

    static func event(from text: String, details: ExtractedDetails, parser: WhenParser) -> CalendarEventDraft {
        let when = parser.parse(text)
        let calendar = parser.calendar
        let start = startTime(when: when, details: details, text: text)
        let day = day(when: when, details: details, start: start, parser: parser, text: text)

        guard let start, let startDate = calendar.date(bySettingHour: start.hour, minute: start.minute, second: 0, of: day) else {
            return CalendarEventDraft(title: title(details.title, text: text, kind: .event), start: day, end: day,
                                      isAllDay: true, location: location(details.location, text: text),
                                      notes: notes(for: text))
        }

        var endDate = startDate.addingTimeInterval(defaultDuration)
        if let end = when.end, let date = calendar.date(bySettingHour: end.hour, minute: end.minute, second: 0, of: day) {
            endDate = date > startDate ? date : calendar.date(byAdding: .day, value: 1, to: date) ?? date
        } else if let minutes = when.durationMinutes, minutes > 0 {
            endDate = startDate.addingTimeInterval(TimeInterval(minutes * 60))
        }
        return CalendarEventDraft(title: title(details.title, text: text, kind: .event), start: startDate, end: endDate,
                                  isAllDay: false, location: location(details.location, text: text),
                                  notes: notes(for: text))
    }

    static func reminder(from text: String, details: ExtractedDetails, parser: WhenParser) -> ReminderDraft {
        let when = parser.parse(text)
        let calendar = parser.calendar
        let time = startTime(when: when, details: details, text: text, useOccasion: false)
        let explicitDay = when.day ?? dayFromModel(details, start: time, parser: parser)
        let hasDate = explicitDay != nil || time != nil
        let day = explicitDay ?? defaultDay(for: time, parser: parser)
        var due = day
        if let time, let date = calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: day) {
            due = date
        }
        return ReminderDraft(title: title(details.title, text: text, kind: .reminder), hasDueDate: hasDate, due: due,
                             hasDueTime: time != nil, notes: notes(for: text))
    }

    // MARK: Parts

    private static func startTime(when: ParsedWhen, details: ExtractedDetails, text: String,
                                  useOccasion: Bool = true) -> ClockTime? {
        if let start = when.start { return start }
        let normalized = WhenParser.normalize(text)
        let hinted = when.dayPart != nil || when.occasionTime != nil
            || WhenParser.contains(normalized, any: ["alle", "ore", "at", "verso", "around", "entro", "by"])
        if hinted, let model = ClockTime(hhmm: details.startTime) { return model }
        if useOccasion, let occasion = when.occasionTime { return occasion }
        return when.dayPart?.defaultTime
    }

    private static func day(when: ParsedWhen, details: ExtractedDetails, start: ClockTime?,
                            parser: WhenParser, text: String) -> Date {
        when.day ?? dayFromModel(details, start: start, parser: parser) ?? detectedDay(in: text, parser: parser)
            ?? defaultDay(for: start, parser: parser)
    }

    /// The model's copy of the day words, parsed here.
    private static func dayFromModel(_ details: ExtractedDetails, start: ClockTime?, parser: WhenParser) -> Date? {
        let words = WhenParser.normalize(details.dayText)
        guard !words.isEmpty else { return nil }
        return parser.day(in: words, start: start)
    }

    /// Last resort for phrasings the parser doesn't know.
    private static func detectedDay(in text: String, parser: WhenParser) -> Date? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue),
              let match = detector.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let date = match.date else { return nil }
        return parser.calendar.startOfDay(for: date)
    }

    /// No day in the text: today if the time is still ahead, else tomorrow.
    private static func defaultDay(for start: ClockTime?, parser: WhenParser) -> Date {
        let calendar = parser.calendar
        let today = calendar.startOfDay(for: parser.now)
        guard let start else { return today }
        let nowMinutes = calendar.component(.hour, from: parser.now) * 60 + calendar.component(.minute, from: parser.now)
        return start.minutesSinceMidnight > nowMinutes ? today : calendar.date(byAdding: .day, value: 1, to: today) ?? today
    }

    static func title(_ raw: String, text: String, kind: DraftKind) -> String {
        var title = clean(raw)
        // The model sometimes keeps only the verb ("Chiamare"): use the text, minus the day and time.
        let fromText = clean(withoutWhen(text))
        let words = { (value: String) in value.split(whereSeparator: \.isWhitespace).count }
        if title.isEmpty || isPlaceholder(title) || (words(title) < 2 && words(fromText) > words(title)) {
            title = fromText.split(whereSeparator: \.isWhitespace).prefix(8).joined(separator: " ")
        }
        guard let first = title.first else { return title }
        return first.uppercased() + title.dropFirst()
    }

    private static func clean(_ value: String) -> String {
        var title = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixes = ["ricordami di ", "ricordami ", "remind me to ", "remind me ", "promemoria: ", "reminder: "]
        for prefix in prefixes where title.lowercased().hasPrefix(prefix) {
            title = String(title.dropFirst(prefix.count))
        }
        return title.trimmingCharacters(in: CharacterSet(charactersIn: " .,;:!?\"“”«»'"))
    }

    /// The text without day and time words ("domani alle 10", "next Tuesday at 3pm").
    static func withoutWhen(_ text: String) -> String {
        let days = "oggi|domani|dopodomani|stasera|stamattina|stanotte|today|tomorrow|tonight"
            + "|lunedi|lunedì|martedi|martedì|mercoledi|mercoledì|giovedi|giovedì|venerdi|venerdì|sabato|domenica"
            + "|monday|tuesday|wednesday|thursday|friday|saturday|sunday"
        let patterns = [
            #"(?i)\b(?:(?:il|la|next|this|on|questo|questa|prossimo|prossima)\s+)?(?:"# + days + #")(?:\s+(?:prossimo|prossima|mattina|pomeriggio|sera|morning|afternoon|evening))?\b"#,
            #"(?i)\b(?:alle(?:\s+ore)?|ore|at|verso\s+le|by|entro\s+le)\s+\d{1,2}(?:[:.]\d{2})?\s*(?:am|pm)?(?:\s+e\s+(?:mezza|mezzo|un\s+quarto))?"#,
            #"(?i)\b\d{1,2}:\d{2}\s*(?:am|pm)?|\b\d{1,2}\s*(?:am|pm)\b"#,
        ]
        var result = text
        for pattern in patterns {
            result = result.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }
        return result.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Keeps the model's place only if the text really mentions it.
    static func location(_ raw: String, text: String) -> String {
        let place = raw.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".,")))
        guard !place.isEmpty, !isPlaceholder(place),
              WhenParser.normalize(text).contains(WhenParser.normalize(place)) else { return "" }
        return place
    }

    private static func notes(for text: String) -> String {
        TextMetrics.wordCount(text) > notesWordThreshold ? String(text.prefix(1000)) : ""
    }

    private static func isPlaceholder(_ value: String) -> Bool {
        ["empty", "none", "null", "n/a", "nil", "nessuno", "nessuna", "vuoto", "unknown", "-"]
            .contains(value.lowercased())
    }
}
