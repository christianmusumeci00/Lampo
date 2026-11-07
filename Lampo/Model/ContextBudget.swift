import Foundation

/// Keeps a prompt inside the model's context window (spec §3.5).
///
/// Before sending, the context texts (selection, clipboard) are measured with
/// `tokenCount(for:)` against `contextSize`, minus what the rest of the request needs.
/// A text that doesn't fit is cut to its beginning and end, joined by "[…]".
struct ContextBudget: Sendable {
    /// Tokens left free for the answer.
    static let answerReserve = 1000
    /// `tokenCount(for:)` can't measure image attachments (it throws on macOS 27), so each
    /// screenshot gets a conservative fixed estimate. See docs/DECISIONS.md.
    static let imageReserve = 1000
    /// Marks where text was cut.
    static let gap = "\n\n[…]\n\n"
    /// Share of an excerpt taken from the beginning of the text (the rest is the end).
    static let headShare = 2.0 / 3.0

    struct Fitted: Equatable {
        var texts: [String?]
        var wasTruncated: Bool
    }

    let model: any ModelService

    /// Fits `texts` into what `route`'s window has left after `fixed` (instructions, template,
    /// history), `images` screenshots and the answer. When they don't fit, each text gets a
    /// share of the room proportional to its size.
    func fit(_ texts: [String?], route: ModelRoute, fixed: [String], images: Int = 0) async -> Fitted {
        let size = await model.contextSize(for: route)
        var used = 0
        for text in fixed where !text.isEmpty {
            used += await count(text)
        }
        let available = max(size - used - Self.answerReserve - images * Self.imageReserve, 0)

        var counts = Array(repeating: 0, count: texts.count)
        for (index, text) in texts.enumerated() {
            if let text, !text.isEmpty { counts[index] = await count(text) }
        }
        let total = counts.reduce(0, +)
        guard total > available else { return Fitted(texts: texts, wasTruncated: false) }

        var fitted: [String?] = []
        for (index, text) in texts.enumerated() {
            guard let text, counts[index] > 0 else {
                fitted.append(text)
                continue
            }
            let share = Int(Double(available) * Double(counts[index]) / Double(total))
            fitted.append(await fit(text, limit: share, tokens: counts[index]))
        }
        return Fitted(texts: fitted, wasTruncated: true)
    }

    /// Cuts `text` (which measures `tokens`) to at most `limit` tokens, keeping its beginning and end.
    func fit(_ text: String, limit: Int, tokens: Int? = nil) async -> String {
        let measured: Int
        if let tokens { measured = tokens } else { measured = await count(text) }
        guard measured > limit else { return text }
        guard limit > 0 else { return "" }

        // Characters per token varies by language: start from the measured ratio, then correct.
        var keep = Int(Double(text.count) * Double(limit) / Double(measured) * 0.95)
        for _ in 0..<5 {
            let candidate = Self.excerpt(text, keeping: keep)
            let size = await count(candidate)
            if size <= limit { return candidate }
            keep = Int(Double(keep) * Double(limit) / Double(size) * 0.9)
            if keep <= 0 { return "" }
        }
        return Self.excerpt(text, keeping: keep)
    }

    /// Token count, or a conservative estimate when the model can't count right now.
    func count(_ text: String) async -> Int {
        if let tokens = try? await model.tokenCount(text) { return tokens }
        return Self.estimate(text)
    }

    /// About 3 bytes of UTF-8 per token: errs on the side of more tokens.
    static func estimate(_ text: String) -> Int {
        text.utf8.count / 3 + 1
    }

    /// The first ⅔ and last ⅓ of `count` characters, cut at word boundaries.
    static func excerpt(_ text: String, keeping count: Int) -> String {
        guard count < text.count else { return text }
        guard count > 0 else { return "" }
        let headCount = Int(Double(count) * headShare)
        let tailCount = count - headCount

        let headEnd = text.index(text.startIndex, offsetBy: headCount)
        var head = text[..<headEnd]
        if !text[headEnd].isWhitespace, let cut = head.lastIndex(where: \.isWhitespace),
           head.distance(from: head.startIndex, to: cut) > headCount / 2 {
            head = head[..<cut]
        }
        let tailStart = text.index(text.endIndex, offsetBy: -tailCount)
        var tail = text[tailStart...]
        if !text[text.index(before: tailStart)].isWhitespace, let cut = tail.firstIndex(where: \.isWhitespace),
           tail.distance(from: cut, to: tail.endIndex) > tailCount / 2 {
            tail = tail[tail.index(after: cut)...]
        }
        let trimmedHead = head.replacing(/\s+$/, with: "")
        let trimmedTail = tail.replacing(/^\s+/, with: "")
        return trimmedHead + gap + trimmedTail
    }
}
