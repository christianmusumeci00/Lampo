import SwiftUI

/// Renders (possibly partial) Markdown: headings, paragraphs, lists, quotes, code.
struct MarkdownView: View {
    let text: String

    var body: some View {
        let blocks = MarkdownParser.parse(text)
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .font(.system(size: DesignTokens.Panel.bodyFontSize))
        .lineSpacing(DesignTokens.Panel.bodyLineSpacing)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(Self.inline(text))
                .font(.system(size: level <= 1 ? 19 : level == 2 ? 17 : 15, weight: .semibold))
                .padding(.top, 2)
        case .paragraph(let text):
            Text(Self.inline(text))
                .fixedSize(horizontal: false, vertical: true)
        case .bulletList(let items, let level):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(verbatim: level == 0 ? "•" : "◦").foregroundStyle(.secondary)
                        Text(Self.inline(item)).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.leading, CGFloat(level) * 22)
        case .orderedList(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(verbatim: "\(item.number).")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        Text(Self.inline(item.text)).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        case .quote(let text):
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(.tertiary)
                    .frame(width: 3)
                Text(Self.inline(text))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .code(_, let code):
            ScrollView(.horizontal) {
                Text(verbatim: code)
                    .font(.system(size: 13, design: .monospaced))
                    .lineSpacing(3)
                    .padding(12)
            }
            .scrollIndicators(.never)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.quaternary.opacity(0.5))
            )
        }
    }

    static func inline(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: false,
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}
