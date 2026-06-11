import Foundation

// MARK: - Block types

/// Block-level elements produced by the markdown parser.
/// Inline content is preserved as raw markdown strings so the rendering layer
/// (SwiftUI / AttributedString) can handle bold, italic, code, and links.
public enum MarkdownBlock: Equatable {
    case heading(level: Int, text: String)
    case paragraph(text: String)
    case bulletItem(text: String)
    case orderedItem(index: Int, text: String)
    case taskItem(checked: Bool, text: String)
    case blockquote(text: String)
    case codeBlock(code: String, language: String?)
    case horizontalRule
}

// MARK: - Parser output

public struct ParsedMarkdownBody: Equatable {
    public let rawSource: String
    public let blocks: [MarkdownBlock]

    public init(rawSource: String, blocks: [MarkdownBlock]) {
        self.rawSource = rawSource
        self.blocks = blocks
    }
}

// MARK: - MarkdownBodyParser

public struct MarkdownBodyParser {

    public static func parse(_ markdown: String) -> ParsedMarkdownBody {
        let blocks = parseBlocks(markdown)
        return ParsedMarkdownBody(rawSource: markdown, blocks: blocks)
    }

    // MARK: - Internal

    static func parseBlocks(_ markdown: String) -> [MarkdownBlock] {
        var lines = markdown.components(separatedBy: .newlines)
        var blocks: [MarkdownBlock] = []
        var i = 0

        while i < lines.count {
            let line = lines[i]

            // Fenced code block
            if line.hasPrefix("```") {
                let lang = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                i += 1
                while i < lines.count && !lines[i].hasPrefix("```") {
                    codeLines.append(lines[i])
                    i += 1
                }
                blocks.append(.codeBlock(
                    code: codeLines.joined(separator: "\n"),
                    language: lang.isEmpty ? nil : lang
                ))
                i += 1
                continue
            }

            // Heading
            if let heading = parseHeading(line) {
                blocks.append(heading)
                i += 1
                continue
            }

            // Horizontal rule
            if isHorizontalRule(line) {
                blocks.append(.horizontalRule)
                i += 1
                continue
            }

            // Blockquote
            if line.hasPrefix("> ") {
                let text = String(line.dropFirst(2))
                blocks.append(.blockquote(text: text))
                i += 1
                continue
            }
            if line == ">" {
                blocks.append(.blockquote(text: ""))
                i += 1
                continue
            }

            // Task item: - [ ] or - [x] or * [ ] or * [x]
            if let task = parseTaskItem(line) {
                blocks.append(task)
                i += 1
                continue
            }

            // Bullet item: - or *
            if let bullet = parseBulletItem(line) {
                blocks.append(bullet)
                i += 1
                continue
            }

            // Ordered item: 1. 2. etc.
            if let ordered = parseOrderedItem(line) {
                blocks.append(ordered)
                i += 1
                continue
            }

            // Blank line — skip
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                i += 1
                continue
            }

            // Paragraph: accumulate consecutive non-special lines
            var paraLines: [String] = [line]
            i += 1
            while i < lines.count {
                let next = lines[i]
                if next.trimmingCharacters(in: .whitespaces).isEmpty { break }
                if parseHeading(next) != nil { break }
                if isHorizontalRule(next) { break }
                if next.hasPrefix("> ") || next == ">" { break }
                if parseTaskItem(next) != nil { break }
                if parseBulletItem(next) != nil { break }
                if parseOrderedItem(next) != nil { break }
                if next.hasPrefix("```") { break }
                paraLines.append(next)
                i += 1
            }
            blocks.append(.paragraph(text: paraLines.joined(separator: "\n")))
        }

        return blocks
    }

    // MARK: - Line parsers

    private static func parseHeading(_ line: String) -> MarkdownBlock? {
        var level = 0
        for ch in line {
            if ch == "#" { level += 1 } else { break }
        }
        guard level > 0, level <= 6 else { return nil }
        let rest = line.dropFirst(level)
        guard rest.hasPrefix(" ") else { return nil }
        let text = String(rest.dropFirst()).trimmingCharacters(in: .whitespaces)
        return .heading(level: level, text: text)
    }

    private static func isHorizontalRule(_ line: String) -> Bool {
        let stripped = line.trimmingCharacters(in: .whitespaces)
        guard stripped.count >= 3 else { return false }
        let chars = Set(stripped.filter { !$0.isWhitespace })
        return chars.count == 1 && (chars.first == "-" || chars.first == "*" || chars.first == "_")
    }

    private static func parseTaskItem(_ line: String) -> MarkdownBlock? {
        let prefixes = ["- [ ] ", "- [x] ", "- [X] ", "* [ ] ", "* [x] ", "* [X] ",
                        "- [ ]", "- [x]", "- [X]", "* [ ]", "* [x]", "* [X]"]
        for prefix in prefixes {
            if line.hasPrefix(prefix) {
                let checked = prefix.contains("[x]") || prefix.contains("[X]")
                let text = String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                return .taskItem(checked: checked, text: text)
            }
        }
        return nil
    }

    private static func parseBulletItem(_ line: String) -> MarkdownBlock? {
        for prefix in ["- ", "* ", "+ "] {
            if line.hasPrefix(prefix) {
                let text = String(line.dropFirst(prefix.count))
                return .bulletItem(text: text)
            }
        }
        return nil
    }

    private static func parseOrderedItem(_ line: String) -> MarkdownBlock? {
        // Match: one or more digits followed by ". " or ") "
        var idx = line.startIndex
        var numStr = ""
        while idx < line.endIndex && line[idx].isNumber {
            numStr.append(line[idx])
            idx = line.index(after: idx)
        }
        guard !numStr.isEmpty, let num = Int(numStr), idx < line.endIndex else { return nil }
        let sep = line[idx]
        guard sep == "." || sep == ")" else { return nil }
        let afterSep = line.index(after: idx)
        guard afterSep < line.endIndex, line[afterSep] == " " else { return nil }
        let text = String(line[line.index(after: afterSep)...])
        return .orderedItem(index: num, text: text)
    }
}
