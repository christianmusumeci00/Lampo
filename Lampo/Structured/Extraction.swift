import AppKit
import Contacts
import Foundation

/// What "Extract" pulls out of a text.
enum ExtractKind: String, CaseIterable, Sendable {
    case contact
    case table
    case todos

    var title: String {
        switch self {
        case .contact: return String(localized: "Contact")
        case .table: return String(localized: "Table")
        case .todos: return String(localized: "To-dos")
        }
    }

    var symbol: String {
        switch self {
        case .contact: return "person.crop.circle.badge.plus"
        case .table: return "tablecells"
        case .todos: return "checklist"
        }
    }

    /// The likely kind, from the shape of the text: contact details → contact, rows of
    /// separated values → table, anything else → to-dos. The user can switch in the panel.
    static func guess(for text: String) -> ExtractKind {
        let words = TextMetrics.wordCount(text)
        if words <= 80, ContactDetector.count(in: text) > 0 { return .contact }
        if TableShape.looksTabular(text) { return .table }
        return .todos
    }
}

/// Phone numbers, emails and links (NSDataDetector) in a text.
enum ContactDetector {
    static func count(in text: String) -> Int {
        let types: NSTextCheckingResult.CheckingType = [.phoneNumber, .link]
        guard let detector = try? NSDataDetector(types: types.rawValue) else { return 0 }
        return detector.matches(in: text, range: NSRange(text.startIndex..., in: text)).filter { match in
            match.resultType == .phoneNumber || match.url?.scheme == "mailto"
        }.count
    }
}

/// Three or more lines with the same number (at least one) of the same separator.
enum TableShape {
    static let separators: [String] = ["\t", "|", ";", " - ", ","]

    static func looksTabular(_ text: String) -> Bool {
        let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard lines.count >= 3 else { return false }
        return separators.contains { separator in
            let counts = lines.map { $0.components(separatedBy: separator).count - 1 }
            guard let first = counts.first, first > 0 else { return false }
            return counts.filter { $0 == first }.count >= max(3, lines.count * 3 / 4)
        }
    }

    /// Without the model: the lines split at the separator they share, with no header.
    static func parse(_ text: String) -> ExtractedTable {
        let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard looksTabular(text), let separator = separators.first(where: { separator in
            let counts = lines.map { $0.components(separatedBy: separator).count - 1 }
            guard let first = counts.first, first > 0 else { return false }
            return counts.filter { $0 == first }.count >= max(3, lines.count * 3 / 4)
        }) else { return ExtractedTable() }
        var rows = lines.map { $0.components(separatedBy: separator) }
        // Markdown tables: drop the outer pipes and the "---" line.
        if separator == "|" {
            rows = rows.map { cells in
                var cells = cells
                if cells.first?.trimmingCharacters(in: .whitespaces).isEmpty == true { cells.removeFirst() }
                if cells.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { cells.removeLast() }
                return cells
            }.filter { !$0.allSatisfy { $0.trimmingCharacters(in: CharacterSet(charactersIn: " -:")).isEmpty } }
        }
        return ExtractedTable(rows: rows).normalized()
    }
}

// MARK: Contact

/// An editable contact. Saved by opening a vCard in Contacts, which asks for confirmation;
/// Lampo never reads or writes the address book itself.
struct ContactDraft: Equatable, Sendable {
    var givenName = ""
    var familyName = ""
    var organization = ""
    var jobTitle = ""
    var phones: [String] = []
    var emails: [String] = []
    var address = ""
    var website = ""

    var displayName: String {
        let name = [givenName, familyName].filter { !$0.isEmpty }.joined(separator: " ")
        return name.isEmpty ? organization : name
    }

    var isEmpty: Bool {
        displayName.isEmpty && phones.isEmpty && emails.isEmpty && address.isEmpty && website.isEmpty
    }

    /// Keeps only what the text really contains: the small model sometimes fills a field
    /// with a placeholder or a guess.
    func checked(against text: String) -> ContactDraft {
        let haystack = Self.normalized(text)
        let digits = text.filter(\.isNumber)
        func keep(_ value: String) -> String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !DraftBuilder.isPlaceholder(trimmed),
                  haystack.contains(Self.normalized(trimmed)) else { return "" }
            return trimmed
        }
        var copy = ContactDraft(givenName: keep(givenName), familyName: keep(familyName),
                                organization: keep(organization), jobTitle: keep(jobTitle),
                                address: keep(address), website: keep(website))
        // The small model sometimes repeats the first name as the last name ("Marco Marco").
        if !copy.familyName.isEmpty, Self.normalized(copy.familyName) == Self.normalized(copy.givenName),
           !haystack.contains(Self.normalized("\(copy.givenName) \(copy.familyName)")) {
            copy.familyName = ""
        }
        copy.emails = emails.map(keep).filter { !$0.isEmpty }
        // Phone numbers are compared by their digits: spacing and dots vary.
        copy.phones = phones.compactMap { phone in
            let phoneDigits = phone.filter(\.isNumber)
            guard phoneDigits.count >= 5, digits.contains(phoneDigits) else { return nil }
            return phone.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return copy
    }

    /// Without the model: phone numbers, emails, links and an address found by NSDataDetector.
    static func detected(in text: String) -> ContactDraft {
        var draft = ContactDraft()
        let types: NSTextCheckingResult.CheckingType = [.phoneNumber, .link, .address]
        guard let detector = try? NSDataDetector(types: types.rawValue) else { return draft }
        for match in detector.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range, in: text) else { continue }
            let value = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            switch match.resultType {
            case .phoneNumber:
                if draft.phones.count < 4 { draft.phones.append(value) }
            case .link:
                if match.url?.scheme == "mailto" {
                    if draft.emails.count < 4 { draft.emails.append(value) }
                } else if draft.website.isEmpty {
                    draft.website = value
                }
            case .address:
                if draft.address.isEmpty { draft.address = value.split(whereSeparator: \.isNewline).joined(separator: ", ") }
            default:
                break
            }
        }
        return draft
    }

    /// For "Copy": one detail per line.
    var plainText: String {
        let name = [givenName, familyName].filter { !$0.isEmpty }.joined(separator: " ")
        let role = [jobTitle, organization].filter { !$0.isEmpty }.joined(separator: " · ")
        return ([name, role] + phones + emails + [address, website]).filter { !$0.isEmpty }.joined(separator: "\n")
    }

    static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// vCard 3 data for Contacts.
    func vCard() throws -> Data {
        let contact = CNMutableContact()
        contact.givenName = givenName
        contact.familyName = familyName
        contact.organizationName = organization
        contact.jobTitle = jobTitle
        if givenName.isEmpty && familyName.isEmpty && !organization.isEmpty {
            contact.contactType = .organization
        }
        contact.phoneNumbers = phones.filter { !$0.isEmpty }.map {
            CNLabeledValue(label: CNLabelPhoneNumberMain, value: CNPhoneNumber(stringValue: $0))
        }
        contact.emailAddresses = emails.filter { !$0.isEmpty }.map {
            CNLabeledValue(label: CNLabelWork, value: $0 as NSString)
        }
        if !website.isEmpty {
            contact.urlAddresses = [CNLabeledValue(label: CNLabelURLAddressHomePage, value: website as NSString)]
        }
        if !address.isEmpty {
            let postal = CNMutablePostalAddress()
            postal.street = address
            contact.postalAddresses = [CNLabeledValue(label: CNLabelWork, value: postal)]
        }
        return try CNContactVCardSerialization.data(with: [contact])
    }
}

/// Hands a contact to Contacts as a vCard file. Contacts shows it and asks before adding,
/// so Lampo needs no access to the address book.
enum ContactExporter {
    @MainActor
    static func open(_ contact: ContactDraft) -> Bool {
        do {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Lampo", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let name = contact.displayName.isEmpty ? String(localized: "Contact") : contact.displayName
            let safe = name.replacingOccurrences(of: #"[/:\\]"#, with: " ", options: .regularExpression)
            let url = folder.appendingPathComponent(safe).appendingPathExtension("vcf")
            try contact.vCard().write(to: url, options: .atomic)
            guard let contacts = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.AddressBook") else {
                return NSWorkspace.shared.open(url)
            }
            NSWorkspace.shared.open([url], withApplicationAt: contacts, configuration: NSWorkspace.OpenConfiguration())
            Log.output.info("contact handed to Contacts")
            return true
        } catch {
            Log.output.error("contact export failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}

// MARK: Table

/// A table pulled out of a text. Copied as tab-separated text (cells in Numbers and Excel)
/// or as Markdown.
struct ExtractedTable: Equatable, Sendable {
    var columns: [String] = []
    var rows: [[String]] = []

    var isEmpty: Bool { rows.isEmpty }

    /// Same number of cells in every row (and header), padded with empty cells.
    func normalized() -> ExtractedTable {
        let width = max(columns.count, rows.map(\.count).max() ?? 0)
        guard width > 0 else { return ExtractedTable() }
        func pad(_ cells: [String]) -> [String] {
            let trimmed = cells.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            return Array(trimmed.prefix(width)) + Array(repeating: "", count: max(width - trimmed.count, 0))
        }
        let rows = rows.map(pad).filter { $0.contains { !$0.isEmpty } }
        return ExtractedTable(columns: columns.isEmpty ? [] : pad(columns), rows: rows)
    }

    var tabSeparated: String {
        let clean = { (cell: String) in cell.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: " ") }
        let lines = (columns.isEmpty ? [] : [columns]) + rows
        return lines.map { $0.map(clean).joined(separator: "\t") }.joined(separator: "\n")
    }

    var markdown: String {
        let width = max(columns.count, rows.map(\.count).max() ?? 0)
        guard width > 0 else { return "" }
        let escape = { (cell: String) in cell.replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: " ") }
        let header = columns.isEmpty ? Array(repeating: "", count: width) : columns
        var lines = ["| " + header.map(escape).joined(separator: " | ") + " |",
                     "|" + Array(repeating: " --- |", count: width).joined()]
        lines += rows.map { "| " + $0.map(escape).joined(separator: " | ") + " |" }
        return lines.joined(separator: "\n")
    }
}

// MARK: Lists

/// Turns a short list ("latte, chiamare Luca domani, bolletta venerdì") into one item each.
///
/// The model splits the text (commas are ambiguous: "cena con Marco, giovedì alle 20" is one
/// event), then `reconcile` keeps only items copied from the text, adds back the pieces the
/// model skipped and restores the text's order. See docs/DECISIONS.md.
enum ListSplitter {
    /// Longer texts (an email) are one item: "Extract › To-dos" handles those.
    static let maximumWords = 60
    static let maximumItems = 12

    /// Whether the text may hold several items, so it's worth asking the model.
    static func mayBeList(_ text: String) -> Bool {
        guard TextMetrics.wordCount(text) <= maximumWords else { return false }
        if segments(of: text, splittingCommas: true).count > 1 { return true }
        let normalized = " " + WhenParser.normalize(text) + " "
        return [" e ", " and ", " poi ", " then "].contains { normalized.contains($0) }
    }

    /// Pieces between list separators: new lines, bullets, semicolons and (optionally) commas.
    static func segments(of text: String, splittingCommas: Bool) -> [String] {
        let pattern = splittingCommas ? #"[\n;,•·]+"# : #"[\n;•·]+"#
        return text.replacingOccurrences(of: pattern, with: "\u{1F}", options: .regularExpression)
            .split(separator: "\u{1F}")
            .map { cleanItem(String($0)) }
            .filter { !$0.isEmpty }
    }

    /// Without the model: new lines, bullets and semicolons only.
    static func fallback(_ text: String) -> [String] {
        let items = segments(of: text, splittingCommas: false)
        return items.count > 1 ? Array(items.prefix(maximumItems)) : [text]
    }

    /// The model's items, checked against the text: items not copied from it are dropped; of
    /// overlapping items the finer ones win ("dentista giovedì" over "dentista giovedì e palestra");
    /// when the model saw a list, the pieces it skipped come back; the text's order is restored.
    static func reconcile(source: String, items: [String]) -> [String] {
        let haystack = key(source)
        func span(of text: String, from start: Int = 0) -> Range<Int>? {
            let itemKey = key(text)
            guard !itemKey.isEmpty, start <= haystack.count else { return nil }
            let from = haystack.index(haystack.startIndex, offsetBy: start)
            guard let range = haystack.range(of: itemKey, range: from..<haystack.endIndex) else { return nil }
            let lower = haystack.distance(from: haystack.startIndex, to: range.lowerBound)
            return lower..<(lower + itemKey.count)
        }

        var accepted: [(span: Range<Int>, text: String)] = []
        let candidates = items.map(cleanItem).compactMap { item in span(of: item).map { (span: $0, text: item) } }
        for candidate in candidates.sorted(by: { $0.span.count < $1.span.count })
        where !accepted.contains(where: { $0.span.overlaps(candidate.span) }) {
            accepted.append(candidate)
        }

        // Pieces the model dropped ("latte" in "latte, chiamare Luca domani"), only when it saw a list:
        // a greeting before a single request isn't an item.
        if accepted.count > 1 {
            var position = 0
            for piece in pieces(of: source) {
                guard let range = span(of: piece, from: position) else { continue }
                position = range.upperBound
                if !isFragment(piece), !accepted.contains(where: { $0.span.overlaps(range) }) {
                    accepted.append((range, piece))
                }
            }
        }

        // A day, time or place on its own ("giovedì alle 20 da Gino") belongs to the item before it.
        var merged: [String] = []
        for item in accepted.sorted(by: { $0.span.lowerBound < $1.span.lowerBound }).map(\.text) {
            if isFragment(item), let last = merged.last {
                merged[merged.count - 1] = last + " " + item
            } else {
                merged.append(item)
            }
        }
        return merged.count > 1 ? Array(merged.prefix(maximumItems)) : [source]
    }

    /// The text cut at every separator, "e"/"and" included: candidates for the pieces the model skipped.
    static func pieces(of text: String) -> [String] {
        segments(of: text, splittingCommas: true).flatMap { segment in
            segment.replacingOccurrences(of: #"\s+(?:e|and|poi|then)\s+"#, with: "\u{1F}",
                                         options: [.regularExpression, .caseInsensitive])
                .split(separator: "\u{1F}").map { cleanItem(String($0)) }.filter { !$0.isEmpty }
        }
    }

    /// A piece that can't stand alone: only day/time words, or a place ("da Gino", "at 8").
    static func isFragment(_ text: String) -> Bool {
        let rest = DraftBuilder.withoutWhen(text).trimmingCharacters(in: .whitespacesAndNewlines)
        if rest.isEmpty { return true }
        let first = rest.split(separator: " ").first.map { WhenParser.normalize(String($0)) } ?? ""
        return ["da", "a", "al", "alla", "in", "presso", "at", "on", "with", "con", "per", "e", "and"].contains(first)
            && TextMetrics.wordCount(rest) <= 3
    }

    /// Strips bullets, numbering and stray punctuation.
    static func cleanItem(_ text: String) -> String {
        text.replacingOccurrences(of: #"^\s*(?:[-*•·◦▪︎☐☑✓✔]|\d{1,2}[.)])\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^\s*(?:e|and|poi|then)\s+"#, with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".,;:")))
    }

    private static func key(_ text: String) -> String {
        WhenParser.normalize(text)
            .replacingOccurrences(of: #"[^\p{L}\p{N}]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }
}
