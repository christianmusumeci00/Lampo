import Foundation

/// Links Lampo understands. Only `lampo://ask?q=…` for now: it opens the panel and asks the question,
/// with no selection or screen attached. A link can't run an action or write anything.
enum LampoURL: Equatable {
    /// Opens the panel; with a question, asks it.
    case ask(String?)

    static let scheme = "lampo"
    /// Longer questions are cut: a link is not the way to send a document.
    static let maxQuestionLength = 2000

    init?(_ url: URL) {
        guard url.scheme?.lowercased() == Self.scheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        // `lampo://ask?q=…` has host "ask"; `lampo:ask?q=…` has path "ask".
        let command = (components.host ?? components.path).lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        switch command {
        case "ask":
            let raw = components.queryItems?.first { $0.name == "q" || $0.name == "question" }?.value ?? ""
            let question = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            self = .ask(question.isEmpty ? nil : String(question.prefix(Self.maxQuestionLength)))
        default:
            return nil
        }
    }
}
