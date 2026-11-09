import Foundation

/// Answers are Markdown (shown formatted in the panel). Insert types them into ordinary text
/// fields, where `**bold**` or `# Title` would show their markers, so it uses plain text.
enum MarkdownText {
    static func plain(_ markdown: String) -> String {
        var isInFence = false
        var lines: [String] = []
        for line in markdown.components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                isInFence.toggle()
                continue
            }
            if isInFence {
                lines.append(line)
                continue
            }
            var text = line
            if let heading = text.range(of: #"^ {0,3}#{1,6}\s+"#, options: .regularExpression) {
                text.removeSubrange(heading)
            }
            lines.append(inlinePlain(text))
        }
        return lines.joined(separator: "\n")
    }

    /// Bold, italics and code lose their markers; a link keeps its address after the text.
    private static func inlinePlain(_ line: String) -> String {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        guard let attributed = try? AttributedString(markdown: line, options: options) else { return line }
        var result = ""
        for run in attributed.runs {
            let text = String(attributed[run.range].characters)
            result += text
            if let url = run.link, url.absoluteString != text,
               url.absoluteString.replacingOccurrences(of: "mailto:", with: "") != text {
                result += " (\(url.absoluteString))"
            }
        }
        return result
    }
}
