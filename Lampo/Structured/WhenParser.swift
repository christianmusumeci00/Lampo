import Foundation

/// A time of day, 24-hour.
struct ClockTime: Equatable, Sendable, CustomStringConvertible {
    var hour: Int
    var minute: Int

    init(hour: Int, minute: Int = 0) {
        self.hour = hour
        self.minute = minute
    }

    /// "20:00", "9:30" → ClockTime; nil for anything else.
    init?(hhmm text: String) {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        self.init(hour: hour, minute: minute)
    }

    var minutesSinceMidnight: Int { hour * 60 + minute }
    var description: String { String(format: "%02d:%02d", hour, minute) }
}

/// Part of the day named in the text ("stasera", "in the morning").
enum DayPart: Equatable, Sendable {
    case morning
    case afternoon
    case evening

    /// Default time when only the part of the day is given.
    var defaultTime: ClockTime {
        switch self {
        case .morning: return ClockTime(hour: 9)
        case .afternoon: return ClockTime(hour: 15)
        case .evening: return ClockTime(hour: 19)
        }
    }
}

/// What a short Italian or English text says about *when*.
struct ParsedWhen: Equatable, Sendable {
    /// Midnight of the day, in the parser's calendar.
    var day: Date?
    var start: ClockTime?
    var end: ClockTime?
    var durationMinutes: Int?
    var dayPart: DayPart?
    /// A meal or occasion with a usual time ("cena" → 20:00).
    var occasionTime: ClockTime?

    /// True when the text gives any hint of a time of day, so a time from the model is plausible.
    var hasTimeCue: Bool { start != nil || dayPart != nil || occasionTime != nil }
}

/// Deterministic parser for dates and times in Italian and English.
///
/// The on-device model is good at pulling the *words* out of a sentence but not at calendar
/// arithmetic ("giovedì" → which date?), and it invents end times. So dates, explicit times,
/// ranges and durations are resolved here, in the user's calendar and time zone.
struct WhenParser {
    var now: Date
    var calendar: Calendar
    /// Month-first numeric dates (US) instead of day-first.
    var monthFirst = false

    init(now: Date = .now, calendar: Calendar = .current, locale: Locale = .current) {
        self.now = now
        self.calendar = calendar
        self.monthFirst = locale.region == .unitedStates
    }

    func parse(_ text: String) -> ParsedWhen {
        let normalized = Self.normalize(text)
        var result = ParsedWhen()
        result.dayPart = Self.dayPart(in: normalized)
        result.occasionTime = Self.occasionTime(in: normalized)
        let times = Self.times(in: normalized, dayPart: result.dayPart)
        result.start = times.start
        result.end = times.end
        result.durationMinutes = Self.duration(in: normalized)
        result.day = day(in: normalized, start: result.start ?? result.occasionTime ?? result.dayPart?.defaultTime)
        return result
    }

    // MARK: Day

    /// The day named in `text` (already normalized), as midnight.
    func day(in text: String, start: ClockTime? = nil) -> Date? {
        let today = calendar.startOfDay(for: now)
        if let date = isoDate(in: text) ?? numericDate(in: text) ?? namedDate(in: text) {
            return date
        }
        if Self.contains(text, any: ["dopodomani", "day after tomorrow"]) {
            return calendar.date(byAdding: .day, value: 2, to: today)
        }
        if Self.contains(text, any: ["domani", "tomorrow"]) {
            return calendar.date(byAdding: .day, value: 1, to: today)
        }
        if Self.contains(text, any: ["oggi", "today", "stasera", "stamattina", "stamani", "stanotte", "tonight", "this morning", "this evening", "this afternoon"]) {
            return today
        }
        if let days = Self.relativeDays(in: text) {
            return calendar.date(byAdding: .day, value: days, to: today)
        }
        if let weekday = Self.weekday(in: text) {
            return nextWeekday(weekday, start: start, today: today)
        }
        return nil
    }

    /// The next occurrence of `weekday` (1 = Sunday). The same weekday as today means today
    /// only if the time is still ahead; otherwise next week.
    private func nextWeekday(_ weekday: Int, start: ClockTime?, today: Date) -> Date? {
        let current = calendar.component(.weekday, from: today)
        var offset = (weekday - current + 7) % 7
        if offset == 0 {
            let nowMinutes = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
            if (start?.minutesSinceMidnight ?? 0) <= nowMinutes { offset = 7 }
        }
        return calendar.date(byAdding: .day, value: offset, to: today)
    }

    private func isoDate(in text: String) -> Date? {
        guard let match = Self.firstMatch(#"\b(\d{4})-(\d{1,2})-(\d{1,2})\b"#, in: text),
              let year = match[1].flatMap(Int.init), let month = match[2].flatMap(Int.init), let day = match[3].flatMap(Int.init) else { return nil }
        return makeDate(year: year, month: month, day: day)
    }

    /// "12/3", "12/3/2027", "12.3." (day first, unless the locale is US).
    private func numericDate(in text: String) -> Date? {
        guard let match = Self.firstMatch(#"\b(\d{1,2})[/.](\d{1,2})(?:[/.](\d{2,4}))?(?!\d)"#, in: text),
              let first = match[1].flatMap(Int.init), let second = match[2].flatMap(Int.init) else { return nil }
        // "20.30" after "alle"/"ore" is a time, not a date.
        if match[3] == nil, text.contains("alle \(first).") || text.contains("ore \(first).") { return nil }
        let (day, month) = monthFirst ? (second, first) : (first, second)
        guard (1...12).contains(month), (1...31).contains(day) else { return nil }
        var year = match[3].flatMap(Int.init)
        if let short = year, short < 100 { year = 2000 + short }
        return resolve(day: day, month: month, year: year)
    }

    /// "12 dicembre", "1° maggio 2027", "December 12th", "dec 3".
    private func namedDate(in text: String) -> Date? {
        let months = Self.monthNames.keys.sorted { $0.count > $1.count }.joined(separator: "|")
        if let match = Self.firstMatch(#"\b(\d{1,2})(?:°|st|nd|rd|th)?\s+(?:di\s+)?("# + months + #")\b\.?(?:\s+(\d{4}))?"#, in: text),
           let day = match[1].flatMap(Int.init), let month = match[2].flatMap({ Self.monthNames[$0] }) {
            return resolve(day: day, month: month, year: match[3].flatMap(Int.init))
        }
        if let match = Self.firstMatch(#"\b("# + months + #")\.?\s+(\d{1,2})(?:st|nd|rd|th)?\b(?:,?\s+(\d{4}))?"#, in: text),
           let month = match[1].flatMap({ Self.monthNames[$0] }), let day = match[2].flatMap(Int.init) {
            return resolve(day: day, month: month, year: match[3].flatMap(Int.init))
        }
        return nil
    }

    /// Without a year, a date already past this year means next year.
    private func resolve(day: Int, month: Int, year: Int?) -> Date? {
        let today = calendar.startOfDay(for: now)
        if let year { return makeDate(year: year, month: month, day: day) }
        let thisYear = calendar.component(.year, from: today)
        guard let date = makeDate(year: thisYear, month: month, day: day) else { return nil }
        return date < today ? makeDate(year: thisYear + 1, month: month, day: day) : date
    }

    private func makeDate(year: Int, month: Int, day: Int) -> Date? {
        let components = DateComponents(year: year, month: month, day: day)
        guard components.isValidDate(in: calendar) else { return nil }
        return calendar.date(from: components)
    }

    // MARK: Time

    /// Explicit start and end times: "alle 20", "dalle 10 alle 11:30", "at 9am", "14:30-15".
    static func times(in text: String, dayPart: DayPart?) -> (start: ClockTime?, end: ClockTime?) {
        let hm = #"(\d{1,2})(?:[:.](\d{2}))?\s*(am|pm)?"#
        // Ranges.
        if let m = firstMatch(#"\b(?:dalle(?: ore)?|from|tra le|between)\s+"# + hm + #"\s+(?:alle|a|to|and|until|till|e le|fino alle)\s+"# + hm + #"\b"#, in: text)
            ?? firstMatch(#"\b"# + hm + #"\s*[-–]\s*"# + hm + #"\b"#, in: text).flatMap({ m in
                // A dash range must look like times (a colon or am/pm), not like a date.
                (m[2] != nil || m[3] != nil || m[5] != nil || m[6] != nil) ? m : nil
            }),
           let start = clock(hour: m[1], minute: m[2], meridiem: m[3], dayPart: dayPart),
           var end = clock(hour: m[4], minute: m[5], meridiem: m[6], dayPart: dayPart) {
            if end.minutesSinceMidnight <= start.minutesSinceMidnight && end.hour < 12 {
                end.hour += 12
            }
            return (start, end.minutesSinceMidnight > start.minutesSinceMidnight ? end : nil)
        }
        // Noon and midnight.
        if contains(text, any: ["mezzogiorno", "noon"]) { return (ClockTime(hour: 12), nil) }
        if contains(text, any: ["mezzanotte", "midnight"]) { return (ClockTime(hour: 0), nil) }
        // A time introduced by a word, or written with a colon or am/pm.
        let patterns = [
            #"\b(?:alle(?: ore)?|ore|h|at|verso le|around|per le|entro le|by)\s+"# + hm + #"\b"#,
            #"\b(\d{1,2}):(\d{2})\s*(am|pm)?\b"#,
            #"\b(\d{1,2})\s*(am|pm)\b"#,
        ]
        for (index, pattern) in patterns.enumerated() {
            guard let m = firstMatch(pattern, in: text) else { continue }
            let meridiem = index == 2 ? m[2] : m[3]
            let minuteText = index == 2 ? nil : m[2]
            guard var time = clock(hour: m[1], minute: minuteText, meridiem: meridiem, dayPart: dayPart) else { continue }
            // "alle 8 e mezza", "alle 9 e un quarto".
            if minuteText == nil, let range = text.range(of: m[0] ?? "") {
                // The match may end with the space before "e".
                let rest = text[range.upperBound...].trimmingCharacters(in: .whitespaces)
                if rest.hasPrefix("e mezza") || rest.hasPrefix("e mezzo") || rest.hasPrefix("e trenta") { time.minute = 30 }
                if rest.hasPrefix("e un quarto") { time.minute = 15 }
                if rest.hasPrefix("e tre quarti") { time.minute = 45 }
            }
            return (time, nil)
        }
        return (nil, nil)
    }

    /// 24-hour time from parts. Without am/pm, 1–11 follow the part of the day,
    /// and 1–7 with no part of the day mean the afternoon (nobody books 3 a.m.).
    static func clock(hour hourText: String?, minute minuteText: String?, meridiem: String?, dayPart: DayPart?) -> ClockTime? {
        guard let hourText, var hour = Int(hourText) else { return nil }
        let minute = minuteText.flatMap(Int.init) ?? 0
        guard (0...24).contains(hour), (0...59).contains(minute) else { return nil }
        if hour == 24 { hour = 0 }
        switch meridiem {
        case "pm": if hour < 12 { hour += 12 }
        case "am": if hour == 12 { hour = 0 }
        default:
            if (1...11).contains(hour) {
                switch dayPart {
                case .afternoon, .evening: hour += 12
                case .morning: break
                case nil: if hour <= 7 { hour += 12 }
                }
            }
        }
        return ClockTime(hour: hour, minute: minute)
    }

    /// "per 30 minuti", "for an hour", "per un'ora e mezza", "for 2 hours".
    static func duration(in text: String) -> Int? {
        if contains(text, any: ["per mezz'ora", "per mezzora", "for half an hour", "for 30 min"]) { return 30 }
        if contains(text, any: ["per un'ora e mezza", "per un'ora e mezzo", "for an hour and a half", "for one and a half hours"]) { return 90 }
        if contains(text, any: ["per un'ora", "per una ora", "for an hour", "for one hour"]) { return 60 }
        if let m = firstMatch(#"\b(?:per|for)\s+(\d{1,3})\s*(minuti|minuto|min|minutes|minute|mins)\b"#, in: text), let n = m[1].flatMap(Int.init) {
            return n
        }
        if let m = firstMatch(#"\b(?:per|for)\s+(\d{1,2}|due|tre|quattro|two|three|four)\s*(ore|ora|hours|hour|h)\b"#, in: text),
           let n = m[1].flatMap({ Int($0) ?? numberWords[$0] }) {
            return n * 60
        }
        return nil
    }

    static func dayPart(in text: String) -> DayPart? {
        if contains(text, any: ["stasera", "sera", "serata", "stanotte", "evening", "tonight", "night"]) { return .evening }
        if contains(text, any: ["pomeriggio", "afternoon"]) { return .afternoon }
        if contains(text, any: ["mattina", "mattino", "stamattina", "stamani", "morning"]) { return .morning }
        return nil
    }

    /// Usual time of a meal or occasion named in the text.
    static func occasionTime(in text: String) -> ClockTime? {
        if contains(text, any: ["colazione", "breakfast"]) { return ClockTime(hour: 8, minute: 30) }
        if contains(text, any: ["pranzo", "lunch"]) { return ClockTime(hour: 13) }
        if contains(text, any: ["aperitivo", "drinks"]) { return ClockTime(hour: 19) }
        if contains(text, any: ["cena", "dinner"]) { return ClockTime(hour: 20) }
        return nil
    }

    // MARK: Words

    static let monthNames: [String: Int] = [
        "gennaio": 1, "febbraio": 2, "marzo": 3, "aprile": 4, "maggio": 5, "giugno": 6, "luglio": 7,
        "agosto": 8, "settembre": 9, "ottobre": 10, "novembre": 11, "dicembre": 12,
        "gen": 1, "mag": 5, "giu": 6, "lug": 7, "ago": 8, "set": 9, "ott": 10, "dic": 12,
        "january": 1, "february": 2, "march": 3, "april": 4, "may": 5, "june": 6, "july": 7,
        "august": 8, "september": 9, "october": 10, "november": 11, "december": 12,
        "jan": 1, "feb": 2, "mar": 3, "apr": 4, "jun": 6, "jul": 7, "aug": 8, "sep": 9, "sept": 9,
        "oct": 10, "nov": 11, "dec": 12,
    ]

    /// Calendar weekday numbers (1 = Sunday).
    static let weekdayNames: [String: Int] = [
        "domenica": 1, "lunedi": 2, "martedi": 3, "mercoledi": 4, "giovedi": 5, "venerdi": 6, "sabato": 7,
        "sunday": 1, "monday": 2, "tuesday": 3, "wednesday": 4, "thursday": 5, "friday": 6, "saturday": 7,
    ]

    static let numberWords: [String: Int] = [
        "un": 1, "una": 1, "uno": 1, "a": 1, "one": 1, "due": 2, "two": 2, "tre": 3, "three": 3,
        "quattro": 4, "four": 4, "cinque": 5, "five": 5, "sei": 6, "six": 6, "sette": 7, "seven": 7,
    ]

    static func weekday(in text: String) -> Int? {
        for (name, number) in weekdayNames where firstMatch(#"\b"# + name + #"\b"#, in: text) != nil {
            return number
        }
        return nil
    }

    /// "tra 3 giorni", "fra una settimana", "in 2 days", "next week".
    static func relativeDays(in text: String) -> Int? {
        if let m = firstMatch(#"\b(?:tra|fra|in)\s+(\d{1,2}|un|una|due|tre|quattro|cinque|sei|sette|a|one|two|three|four|five|six|seven)\s+(giorni|giorno|days|day|settimane|settimana|weeks|week)\b"#, in: text),
           let n = m[1].flatMap({ Int($0) ?? numberWords[$0] }), let unit = m[2] {
            return unit.hasPrefix("settiman") || unit.hasPrefix("week") ? n * 7 : n
        }
        if contains(text, any: ["la settimana prossima", "la prossima settimana", "next week"]) { return 7 }
        return nil
    }

    // MARK: Helpers

    /// Lowercased, without accents, straight apostrophes, single spaces.
    static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en"))
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    static func contains(_ text: String, any phrases: [String]) -> Bool {
        phrases.contains { firstMatch(#"(?<![\p{L}\d])"# + NSRegularExpression.escapedPattern(for: $0) + #"(?![\p{L}\d])"#, in: text) != nil }
    }

    /// Capture groups of the first match (index 0 is the whole match); nil groups didn't match.
    static func firstMatch(_ pattern: String, in text: String) -> [String?]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (0..<match.numberOfRanges).map { index in
            Range(match.range(at: index), in: text).map { String(text[$0]) }
        }
    }
}
