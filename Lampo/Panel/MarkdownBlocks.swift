import Foundation

/// Block-level Markdown for streamed answers. SwiftUI's `AttributedString(markdown:)`
/// handles inline syntax only, so lists, headings and code fences are split here.
/// Tolerates partial input: an unclosed fence renders as code while streaming.
enum MarkdownBlock: Equatable, Sendable {
    case heading(level: Int, text: String)
    case paragraph(String)
    /// `level` is 0 for top-level lists, 1+ for lists nested under another item.
    case bulletList([String], level: Int = 0)
    case orderedList([(number: Int, text: String)])
    case code(language: String?, code: String)
    case quote(String)

    static func == (lhs: MarkdownBlock, rhs: MarkdownBlock) -> Bool {
        switch (lhs, rhs) {
        case let (.heading(l1, t1), .heading(l2, t2)): return l1 == l2 && t1 == t2
        case let (.paragraph(a), .paragraph(b)): return a == b
        case let (.bulletList(a, l1), .bulletList(b, l2)): return a == b && l1 == l2
        case let (.orderedList(a), .orderedList(b)):
            return a.count == b.count && zip(a, b).allSatisfy { $0.number == $1.number && $0.text == $1.text }
        case let (.code(l1, c1), .code(l2, c2)): return l1 == l2 && c1 == c2
        case let (.quote(a), .quote(b)): return a == b
        default: return false
        }
    }
}

enum MarkdownParser {
    static func parse(_ text: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var bullets: [String] = []
        var bulletLevel = 0
        var ordered: [(Int, String)] = []
        var quote: [String] = []
        var codeLines: [String]?
        var codeLanguage: String?

        func flushParagraph() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: "\n"))) }
            paragraph = []
        }
        func flushLists() {
            if !bullets.isEmpty { blocks.append(.bulletList(bullets, level: bulletLevel)) }
            if !ordered.isEmpty { blocks.append(.orderedList(ordered.map { (number: $0.0, text: $0.1) })) }
            if !quote.isEmpty { blocks.append(.quote(quote.joined(separator: "\n"))) }
            bullets = []; ordered = []; quote = []
        }
        func flushAll() { flushParagraph(); flushLists() }

        for rawLine in text.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if var lines = codeLines {
                if line.hasPrefix("```") {
                    blocks.append(.code(language: codeLanguage, code: lines.joined(separator: "\n")))
                    codeLines = nil
                    codeLanguage = nil
                } else {
                    lines.append(rawLine)
                    codeLines = lines
                }
                continue
            }

            if line.hasPrefix("```") {
                flushAll()
                let language = line.dropFirst(3).trimmingCharacters(in: .whitespaces)
                codeLanguage = language.isEmpty ? nil : language
                codeLines = []
                continue
            }

            if line.isEmpty {
                flushAll()
                continue
            }

            if let heading = parseHeading(line) {
                flushAll()
                blocks.append(heading)
                continue
            }

            if let item = parseBullet(line) {
                flushParagraph()
                let level = min(rawLine.prefix { $0 == " " || $0 == "\t" }.count / 2, 3)
                if !ordered.isEmpty || !quote.isEmpty || (!bullets.isEmpty && level != bulletLevel) { flushLists() }
                bulletLevel = level
                bullets.append(item)
                continue
            }

            if let item = parseOrdered(line) {
                flushParagraph()
                if !bullets.isEmpty || !quote.isEmpty { flushLists() }
                ordered.append(item)
                continue
            }

            if line.hasPrefix(">") {
                flushParagraph()
                if !bullets.isEmpty || !ordered.isEmpty { flushLists() }
                quote.append(String(line.dropFirst()).trimmingCharacters(in: .whitespaces))
                continue
            }

            // Continuation of a list item (indented line) or a plain paragraph line.
            if rawLine.hasPrefix("  "), !bullets.isEmpty {
                bullets[bullets.count - 1] += " " + line
            } else if rawLine.hasPrefix("  "), !ordered.isEmpty {
                ordered[ordered.count - 1].1 += " " + line
            } else {
                flushLists()
                paragraph.append(line)
            }
        }

        if let lines = codeLines {
            blocks.append(.code(language: codeLanguage, code: lines.joined(separator: "\n")))
        }
        flushAll()
        return blocks
    }

    private static func parseHeading(_ line: String) -> MarkdownBlock? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes) else { return nil }
        let rest = line.dropFirst(hashes)
        guard rest.first == " " else { return nil }
        return .heading(level: hashes, text: rest.trimmingCharacters(in: .whitespaces))
    }

    private static func parseBullet(_ line: String) -> String? {
        for marker in ["- ", "* ", "• ", "+ "] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count))
        }
        return nil
    }

    private static func parseOrdered(_ line: String) -> (Int, String)? {
        let digits = line.prefix { $0.isASCII && $0.isNumber }
        guard !digits.isEmpty, digits.count <= 3, let number = Int(digits) else { return nil }
        let rest = line.dropFirst(digits.count)
        guard rest.hasPrefix(". ") || rest.hasPrefix(") ") else { return nil }
        return (number, String(rest.dropFirst(2)))
    }
}
