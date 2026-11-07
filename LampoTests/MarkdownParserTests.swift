import Testing
@testable import Lampo

struct MarkdownParserTests {
    @Test func paragraphsAndHeadings() {
        let blocks = MarkdownParser.parse("# Title\n\nFirst line\nsecond line\n\nAnother")
        #expect(blocks == [
            .heading(level: 1, text: "Title"),
            .paragraph("First line\nsecond line"),
            .paragraph("Another"),
        ])
    }

    @Test func bulletAndOrderedLists() {
        let blocks = MarkdownParser.parse("Intro:\n- one\n- **two**\n\n1. a\n2) b")
        #expect(blocks == [
            .paragraph("Intro:"),
            .bulletList(["one", "**two**"]),
            .orderedList([(number: 1, text: "a"), (number: 2, text: "b")]),
        ])
    }

    @Test func codeFence() {
        let blocks = MarkdownParser.parse("Run:\n```swift\nlet x = 1\n  print(x)\n```\nDone")
        #expect(blocks == [
            .paragraph("Run:"),
            .code(language: "swift", code: "let x = 1\n  print(x)"),
            .paragraph("Done"),
        ])
    }

    @Test func unclosedFenceWhileStreaming() {
        let blocks = MarkdownParser.parse("```\nlet partial")
        #expect(blocks == [.code(language: nil, code: "let partial")])
    }

    @Test func quoteAndHashWithoutSpace() {
        let blocks = MarkdownParser.parse("> quoted\n#hashtag")
        #expect(blocks == [.quote("quoted"), .paragraph("#hashtag")])
    }

    @Test func nestedBulletsUnderOrderedItems() {
        let blocks = MarkdownParser.parse("1. Step:\n   - detail\n2. Next")
        #expect(blocks == [
            .orderedList([(number: 1, text: "Step:")]),
            .bulletList(["detail"], level: 1),
            .orderedList([(number: 2, text: "Next")]),
        ])
    }

    @Test func emptyInput() {
        #expect(MarkdownParser.parse("").isEmpty)
    }
}
