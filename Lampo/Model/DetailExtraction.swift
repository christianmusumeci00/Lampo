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

extension FoundationModelService {
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
}
