import Foundation
import FoundationModels

/// Guided-generation schemas for "Create event" and "Create reminder".
///
/// Only words are generated: the model copies the day words and the start time, and
/// `WhenParser` turns them into dates. A probe showed the small model resolves the words
/// well but invents end times and durations, so those aren't asked for.
@Generable(description: "An event described in the user's text")
struct GeneratedEventDetails {
    @Guide(description: "Short title in the language of the text, e.g. 'Cena con Marco'. No date or time.")
    var title: String
    @Guide(description: "The words of the text that name the day, copied exactly (e.g. 'giovedì', 'domani', 'next Tuesday', '12 dicembre'). Empty if the text names no day.")
    var dayText: String
    @Guide(description: "Start time in 24-hour HH:mm. Empty if the text gives no time.")
    var startTime: String
    @Guide(description: "The place, copied from the text. Empty if the text names no place.")
    var location: String
}

@Generable(description: "A reminder described in the user's text")
struct GeneratedReminderDetails {
    @Guide(description: "The whole task with what and who it is about, starting with a verb, in the language of the text, e.g. 'Chiamare Anna per il preventivo', 'Comprare il latte'. No date or time.")
    var title: String
    @Guide(description: "The words of the text that name the day, copied exactly (e.g. 'domani', 'venerdì', 'tomorrow'). Empty if none.")
    var dayText: String
    @Guide(description: "Time in 24-hour HH:mm. Empty if the text gives no time.")
    var startTime: String
}

@Generable(description: "The separate things to do listed in the user's text")
struct GeneratedSplit {
    @Guide(description: "One entry for each separate thing to do or event, with all its words copied exactly from the text: what, who, day, time and place stay together in one entry. A day, a time or a place is never an entry on its own. Text about one single thing gives exactly one entry.", .maximumCount(12))
    var items: [String]
}

@Generable(description: "Contact details found in the text")
struct GeneratedContact {
    @Guide(description: "Given name. Empty if none.")
    var givenName: String
    @Guide(description: "Family name. Empty if none.")
    var familyName: String
    @Guide(description: "Company or organization. Empty if none.")
    var organization: String
    @Guide(description: "Job title. Empty if none.")
    var jobTitle: String
    @Guide(description: "Phone numbers, copied exactly.", .maximumCount(4))
    var phones: [String]
    @Guide(description: "Email addresses, copied exactly.", .maximumCount(4))
    var emails: [String]
    @Guide(description: "Postal address on one line, copied exactly. Empty if none.")
    var address: String
    @Guide(description: "Website, copied exactly. Empty if none.")
    var website: String
}

@Generable(description: "A row of a table")
struct GeneratedRow {
    @Guide(description: "The cells of the row, in column order")
    var cells: [String]
}

@Generable(description: "The data of the text arranged as a table")
struct GeneratedTable {
    @Guide(description: "Column headers, short, in the language of the text", .maximumCount(8))
    var columns: [String]
    @Guide(description: "One row per record, with one cell per column, copied from the text", .maximumCount(40))
    var rows: [GeneratedRow]
}

@Generable(description: "The tasks in the text")
struct GeneratedTasks {
    @Guide(description: "Each task the reader has to do, starting with a verb, in the language of the text, with its day or deadline words copied if the text gives them. Only real tasks.", .maximumCount(15))
    var items: [String]
}

extension FoundationModelService {
    /// Extraction prompts get at most this much text (about 2000 tokens): beginning and end.
    static let maximumExtractionCharacters = 6000
    static let copyRule = "Copy words from the text. Never invent details: leave a field empty instead."

    static let extractionInstructions = """
        Extract the details of what the user describes in the text between <text> and </text>.
        Copy words from the text. Never invent a day, a time or a place: leave the field empty instead.
        """

    func extractDetails(from text: String, kind: DraftKind) async throws -> ExtractedDetails {
        let availability = availability()
        guard availability.isAvailable else { throw ModelError.unavailable(availability) }
        let session = LanguageModelSession(model: SystemLanguageModel.default, instructions: Self.extractionInstructions)
        let prompt = "<text>\n\(text)\n</text>"
        do {
            switch kind {
            case .event:
                let details = try await session.respond(to: prompt, generating: GeneratedEventDetails.self).content
                return ExtractedDetails(title: details.title, dayText: details.dayText,
                                        startTime: details.startTime, location: details.location)
            case .reminder:
                let details = try await session.respond(to: prompt, generating: GeneratedReminderDetails.self).content
                return ExtractedDetails(title: details.title, dayText: details.dayText, startTime: details.startTime)
            }
        } catch {
            throw FoundationModelConversation.map(error)
        }
    }

    func splitItems(_ text: String) async throws -> [String] {
        try await generate(GeneratedSplit.self, from: text,
                           instructions: "Split the text between <text> and </text> into the separate things to do. " + Self.copyRule).items
    }

    func extractContact(from text: String) async throws -> ContactDraft {
        let contact = try await generate(GeneratedContact.self, from: text,
                                         instructions: "Extract the contact details in the text between <text> and </text>. " + Self.copyRule)
        return ContactDraft(givenName: contact.givenName, familyName: contact.familyName,
                            organization: contact.organization, jobTitle: contact.jobTitle,
                            phones: contact.phones, emails: contact.emails,
                            address: contact.address, website: contact.website)
    }

    func extractTable(from text: String) async throws -> ExtractedTable {
        let table = try await generate(GeneratedTable.self, from: text,
                                       instructions: "Arrange the data in the text between <text> and </text> as a table. " + Self.copyRule)
        return ExtractedTable(columns: table.columns, rows: table.rows.map(\.cells))
    }

    func extractTasks(from text: String) async throws -> [String] {
        try await generate(GeneratedTasks.self, from: text,
                           instructions: "List the tasks in the text between <text> and </text>. " + Self.copyRule).items
    }

    private func generate<Content: Generable>(_ type: Content.Type, from text: String,
                                              instructions: String) async throws -> Content {
        let availability = availability()
        guard availability.isAvailable else { throw ModelError.unavailable(availability) }
        let session = LanguageModelSession(model: SystemLanguageModel.default, instructions: instructions)
        let excerpt = ContextBudget.excerpt(text, keeping: Self.maximumExtractionCharacters)
        do {
            return try await session.respond(to: "<text>\n\(excerpt)\n</text>", generating: type).content
        } catch {
            throw FoundationModelConversation.map(error)
        }
    }
}
