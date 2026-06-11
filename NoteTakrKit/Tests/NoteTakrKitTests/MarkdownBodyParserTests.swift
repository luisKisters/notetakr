import XCTest
@testable import NoteTakrKit

final class MarkdownBodyParserTests: XCTestCase {

    // MARK: - Raw source preservation

    func testRawSourcePreserved() {
        let md = "## Hello\n- item"
        let parsed = MarkdownBodyParser.parse(md)
        XCTAssertEqual(parsed.rawSource, md, "rawSource must equal the input — this is what ⌘C copies")
    }

    func testEmptyInputPreservesEmptySource() {
        let parsed = MarkdownBodyParser.parse("")
        XCTAssertEqual(parsed.rawSource, "")
        XCTAssertTrue(parsed.blocks.isEmpty)
    }

    func testCopyRoundTripComplexDocument() {
        // Simulates the ⌘C "copy raw markdown" path: rawSource must equal the original string exactly.
        let md = "# Title\n\n## Heading\n\n- Item 1\n- Item 2\n\n- [x] Done\n- [ ] Pending\n\n> A blockquote\n\n```swift\nlet x = 1\n```\n\nParagraph text with **bold** and *italic*."
        let parsed = MarkdownBodyParser.parse(md)
        XCTAssertEqual(parsed.rawSource, md, "⌘C must copy the exact raw source verbatim, regardless of how blocks parse")
    }

    func testCopyRoundTripUnicode() {
        let md = "## Meeting Notes\n\n- Action: Review PR #42 \u{2192} Done\n- Blocked: auth-service (team)"
        let parsed = MarkdownBodyParser.parse(md)
        XCTAssertEqual(parsed.rawSource, md)
    }

    func testCopyRoundTripMultilinePreservesNewlines() {
        let md = "Line one\nLine two\n\nLine three"
        let parsed = MarkdownBodyParser.parse(md)
        XCTAssertEqual(parsed.rawSource, md)
    }

    // MARK: - Headings h1–h6

    func testH1() {
        assertBlocks("# Hello", expected: [.heading(level: 1, text: "Hello")])
    }

    func testH2() {
        assertBlocks("## Agenda", expected: [.heading(level: 2, text: "Agenda")])
    }

    func testH3() {
        assertBlocks("### Sub", expected: [.heading(level: 3, text: "Sub")])
    }

    func testH6() {
        assertBlocks("###### Deep", expected: [.heading(level: 6, text: "Deep")])
    }

    func testHeadingWithoutSpace_notAHeading() {
        // "##NoSpace" is a paragraph, not a heading
        let blocks = MarkdownBodyParser.parseBlocks("##NoSpace")
        XCTAssertFalse(blocks.contains(.heading(level: 2, text: "NoSpace")))
    }

    func testHeadingTextTrimmed() {
        assertBlocks("#  Trimmed  ", expected: [.heading(level: 1, text: "Trimmed")])
    }

    // MARK: - Bullet lists

    func testBulletDash() {
        assertBlocks("- First", expected: [.bulletItem(text: "First")])
    }

    func testBulletStar() {
        assertBlocks("* Second", expected: [.bulletItem(text: "Second")])
    }

    func testBulletPlus() {
        assertBlocks("+ Third", expected: [.bulletItem(text: "Third")])
    }

    func testBulletWithInlineCode() {
        assertBlocks("- Onboarding blocked on `auth-service v2`",
                     expected: [.bulletItem(text: "Onboarding blocked on `auth-service v2`")])
    }

    func testMultipleBullets() {
        let md = "- A\n- B\n- C"
        let blocks = MarkdownBodyParser.parseBlocks(md)
        XCTAssertEqual(blocks, [
            .bulletItem(text: "A"),
            .bulletItem(text: "B"),
            .bulletItem(text: "C")
        ])
    }

    // MARK: - Ordered lists

    func testOrderedItem() {
        assertBlocks("1. First step", expected: [.orderedItem(index: 1, text: "First step")])
    }

    func testOrderedItemHighIndex() {
        assertBlocks("42. Some step", expected: [.orderedItem(index: 42, text: "Some step")])
    }

    func testOrderedItemParen() {
        assertBlocks("1) First step", expected: [.orderedItem(index: 1, text: "First step")])
    }

    func testMultipleOrderedItems() {
        let md = "1. Alpha\n2. Beta"
        let blocks = MarkdownBodyParser.parseBlocks(md)
        XCTAssertEqual(blocks, [
            .orderedItem(index: 1, text: "Alpha"),
            .orderedItem(index: 2, text: "Beta")
        ])
    }

    // MARK: - Task items

    func testTaskUnchecked() {
        assertBlocks("- [ ] Do something", expected: [.taskItem(checked: false, text: "Do something")])
    }

    func testTaskCheckedLowercase() {
        assertBlocks("- [x] Done item", expected: [.taskItem(checked: true, text: "Done item")])
    }

    func testTaskCheckedUppercase() {
        assertBlocks("- [X] Also done", expected: [.taskItem(checked: true, text: "Also done")])
    }

    func testTaskWithStarPrefix() {
        assertBlocks("* [ ] Star task", expected: [.taskItem(checked: false, text: "Star task")])
    }

    func testTaskMixedInList() {
        let md = "- [x] Send invoice draft to Acme\n- [ ] Tom: spec the export API by Friday"
        let blocks = MarkdownBodyParser.parseBlocks(md)
        XCTAssertEqual(blocks, [
            .taskItem(checked: true, text: "Send invoice draft to Acme"),
            .taskItem(checked: false, text: "Tom: spec the export API by Friday")
        ])
    }

    // MARK: - Blockquotes

    func testBlockquote() {
        assertBlocks("> A decision was made.", expected: [.blockquote(text: "A decision was made.")])
    }

    func testBlockquotePreservesInlineMarkdown() {
        assertBlocks("> **Bold** decision", expected: [.blockquote(text: "**Bold** decision")])
    }

    func testEmptyBlockquote() {
        assertBlocks(">", expected: [.blockquote(text: "")])
    }

    // MARK: - Fenced code blocks

    func testCodeBlock() {
        let md = "```\nlet x = 1\n```"
        let blocks = MarkdownBodyParser.parseBlocks(md)
        XCTAssertEqual(blocks, [.codeBlock(code: "let x = 1", language: nil)])
    }

    func testCodeBlockWithLanguage() {
        let md = "```swift\nfunc hello() {}\n```"
        let blocks = MarkdownBodyParser.parseBlocks(md)
        XCTAssertEqual(blocks, [.codeBlock(code: "func hello() {}", language: "swift")])
    }

    func testCodeBlockMultiline() {
        let md = "```\nline1\nline2\nline3\n```"
        let blocks = MarkdownBodyParser.parseBlocks(md)
        XCTAssertEqual(blocks, [.codeBlock(code: "line1\nline2\nline3", language: nil)])
    }

    // MARK: - Horizontal rules

    func testHorizontalRuleDashes() {
        assertBlocks("---", expected: [.horizontalRule])
    }

    func testHorizontalRuleStars() {
        assertBlocks("***", expected: [.horizontalRule])
    }

    func testHorizontalRuleUnderscores() {
        assertBlocks("___", expected: [.horizontalRule])
    }

    func testShortDashesNotHorizontalRule() {
        // Two dashes is not a thematic break
        let blocks = MarkdownBodyParser.parseBlocks("--")
        XCTAssertFalse(blocks.contains(.horizontalRule))
    }

    // MARK: - Paragraphs

    func testSimpleParagraph() {
        assertBlocks("Hello world", expected: [.paragraph(text: "Hello world")])
    }

    func testMultilineParagraph() {
        // Two consecutive non-blank lines merge into one paragraph block
        let md = "Line one\nLine two"
        let blocks = MarkdownBodyParser.parseBlocks(md)
        XCTAssertEqual(blocks, [.paragraph(text: "Line one\nLine two")])
    }

    func testBlankLineSeparatesParagraphs() {
        let md = "First\n\nSecond"
        let blocks = MarkdownBodyParser.parseBlocks(md)
        XCTAssertEqual(blocks, [
            .paragraph(text: "First"),
            .paragraph(text: "Second")
        ])
    }

    // MARK: - Mixed document (mirrors editor.html RAW_MD)

    func testMixedDocument() {
        let md = """
## Agenda
- Q3 roadmap freeze — Sarah presents
- Onboarding flow blocked on `auth-service v2`

## Notes
- [x] Send invoice draft to Acme
- [ ] Tom: spec the export API by Friday

> Decision: ship the floating-window beta to 20 pilot users next week.
"""
        let blocks = MarkdownBodyParser.parseBlocks(md)
        XCTAssertEqual(blocks[0], .heading(level: 2, text: "Agenda"))
        XCTAssertEqual(blocks[1], .bulletItem(text: "Q3 roadmap freeze — Sarah presents"))
        XCTAssertEqual(blocks[2], .bulletItem(text: "Onboarding flow blocked on `auth-service v2`"))
        XCTAssertEqual(blocks[3], .heading(level: 2, text: "Notes"))
        XCTAssertEqual(blocks[4], .taskItem(checked: true, text: "Send invoice draft to Acme"))
        XCTAssertEqual(blocks[5], .taskItem(checked: false, text: "Tom: spec the export API by Friday"))
        XCTAssertEqual(blocks[6], .blockquote(text: "Decision: ship the floating-window beta to 20 pilot users next week."))
    }

    // MARK: - Blank lines skipped

    func testBlankLinesProduceNoBlocks() {
        let blocks = MarkdownBodyParser.parseBlocks("\n\n\n")
        XCTAssertTrue(blocks.isEmpty)
    }

    // MARK: - Helpers

    private func assertBlocks(_ md: String, expected: [MarkdownBlock],
                               file: StaticString = #file, line: UInt = #line) {
        let blocks = MarkdownBodyParser.parseBlocks(md)
        XCTAssertEqual(blocks, expected, file: file, line: line)
    }
}
