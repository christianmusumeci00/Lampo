import Foundation

/// System instructions for the model. Kept short: the on-device model is small
/// and follows brief, direct guidance best.
enum SystemInstructions {
    static func general(language: ResponseLanguage) -> String {
        """
        You are Lampo, an assistant built into the user's Mac.
        Be concise and direct. Prefer short paragraphs and lists.
        \(languageRule(language))
        Work on the context the user provides. Do not invent facts, names, numbers or sources; \
        if you are not sure, say so briefly.
        Use Markdown only for emphasis, lists and code.
        """
    }

    static func languageRule(_ language: ResponseLanguage) -> String {
        switch language {
        case .automatic: return "Always answer in the same language the user writes in."
        case .italian: return "Always answer in Italian."
        case .english: return "Always answer in English."
        }
    }

    /// Follow-up prompt for the "Go deeper" button.
    static let goDeeper = "Go deeper: expand on your previous answer with more detail and a concrete example. Keep the same language."
}
