import Foundation
import NaturalLanguage

/// Values available to action templates.
struct TemplateContext: Equatable, Sendable {
    var selection: String?
    var clipboard: String?
    var app: String?
    /// Language name for answers, e.g. "Italian".
    var language: String
    /// For `{{tone}}` ("Rewrite"): the tone picked in the Lens.
    var tone: RewriteTone = .clearer
    /// For `{{dictation}}`: what the user said.
    var dictation: String?

    /// English name of the input's own language ("Italian"), detected on device.
    var textLanguage: String {
        TextLanguage.name(of: selection ?? clipboard ?? dictation ?? "") ?? "the same language as the text"
    }
}

enum TextLanguage {
    /// Dominant language of `text` as an English name, or nil when unsure (very short text).
    static func name(of text: String) -> String? {
        guard text.count >= 12 else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(String(text.prefix(2000)))
        guard let (language, confidence) = recognizer.languageHypotheses(withMaximum: 1).first,
              confidence >= 0.6 else { return nil }
        return Locale(identifier: "en").localizedString(forLanguageCode: language.rawValue)
    }
}

enum PromptTemplate {
    static let variables = ["selection", "clipboard", "dictation", "app", "language", "text_language", "tone"]

    /// Replaces `{{name}}` (spaces inside braces allowed). The input text is fenced so the model
    /// can tell instruction from content. If the template doesn't mention the action's input,
    /// the input is appended, so a custom prompt like "Make it funnier" still works.
    static func render(_ template: String, context: TemplateContext, input: LampoAction.InputSource) -> String {
        var output = template
        var usedInput = false
        for name in variables {
            let pattern = "\\{\\{\\s*\(name)\\s*\\}\\}"
            guard output.range(of: pattern, options: .regularExpression) != nil else { continue }
            let value: String
            switch name {
            case "selection":
                value = fenced(context.selection ?? "")
                if input == .selection { usedInput = true }
            case "clipboard":
                value = fenced(context.clipboard ?? "")
                if input == .clipboard { usedInput = true }
            case "dictation":
                value = fenced(context.dictation ?? "")
                if input == .dictation { usedInput = true }
            case "app":
                value = context.app ?? ""
            case "text_language":
                value = context.textLanguage
            case "tone":
                value = context.tone.instruction
            default:
                value = context.language
            }
            output = output.replacingOccurrences(of: pattern, with: NSRegularExpression.escapedTemplate(for: value),
                                                 options: .regularExpression)
        }
        if !usedInput {
            switch input {
            case .selection:
                if let selection = context.selection { output += "\n\n" + fenced(selection) }
            case .clipboard:
                if let clipboard = context.clipboard { output += "\n\n" + fenced(clipboard) }
            case .dictation:
                if let dictation = context.dictation { output += "\n\n" + fenced(dictation) }
            case .screen, .none:
                break
            }
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Variables used by a template that aren't supported (typos like {{selecton}}).
    static func unknownVariables(in template: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: "\\{\\{\\s*([A-Za-z_]+)\\s*\\}\\}") else { return [] }
        let range = NSRange(template.startIndex..., in: template)
        return regex.matches(in: template, range: range).compactMap { match in
            Range(match.range(at: 1), in: template).map { String(template[$0]) }
        }.filter { !variables.contains($0) }
    }

    static func fenced(_ text: String) -> String {
        "<text>\n\(text)\n</text>"
    }
}

/// Removes the wrapping a small model sometimes adds around rewritten text.
enum RewriteCleaner {
    private static let preamblePrefixes = [
        "here is", "here's", "sure", "certainly", "ecco", "certo", "ok,", "okay,", "di seguito",
    ]

    static func clean(_ output: String, original: String? = nil) -> String {
        var text = output.trimmingCharacters(in: .whitespacesAndNewlines)

        // Drop fences the model copied from the prompt.
        text = text.replacingOccurrences(of: "<text>", with: "").replacingOccurrences(of: "</text>", with: "")
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // "Here is the corrected text:" on its own first line.
        if let newline = text.firstIndex(of: "\n") {
            let first = text[..<newline].trimmingCharacters(in: .whitespaces)
            let lower = first.lowercased()
            if first.hasSuffix(":"), first.count <= 80, preamblePrefixes.contains(where: lower.hasPrefix) {
                text = String(text[text.index(after: newline)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // Wrapping quotes, unless the original itself was quoted.
        let pairs: [(Character, Character)] = [("\"", "\""), ("“", "”"), ("«", "»"), ("'", "'"), ("‘", "’")]
        let originalTrimmed = original?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        for (open, close) in pairs where text.count >= 2 && text.first == open && text.last == close {
            if originalTrimmed.first == open { break }
            let inner = text.dropFirst().dropLast()
            if !inner.contains(open) && !inner.contains(close) {
                text = String(inner).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            break
        }

        // Keep the original's trailing newline, so replacing a whole paragraph doesn't join lines.
        if let original, original.hasSuffix("\n"), !text.hasSuffix("\n") {
            text += "\n"
        }
        return text
    }
}
