import Foundation
import Markdown

// MARK: - MarkdownSyntaxSpan

/// A styled region of markdown source, expressed in UTF-16 offsets so the app
/// layer can map it straight onto an `NSAttributedString` / `NSTextStorage`.
///
/// This is produced by parsing with swift-markdown (cmark-gfm) — a real CommonMark
/// + GFM parser — rather than ad-hoc regexes, so the weird corners of markdown
/// (nested emphasis, code spans, links, setext headings, …) are handled correctly.
public struct MarkdownSyntaxSpan: Equatable {
    public enum Kind: Equatable {
        case heading(level: Int)
        case bold
        case italic
        case strikethrough
        case inlineCode
        case codeBlock
        case link
        case blockQuote
        case listMarker
    }

    public let location: Int   // UTF-16 offset into the source string
    public let length: Int
    public let kind: Kind

    public init(location: Int, length: Int, kind: Kind) {
        self.location = location
        self.length = length
        self.kind = kind
    }
}

// MARK: - Marker ranges

/// A sub-range of the source that is pure markdown syntax (``**``, leading `#␣`,
/// backticks, `>`, list bullet) and should be concealed in the WYSIWYG editor so
/// the text looks rendered. The characters stay in the text storage / `note.md`;
/// only their glyphs are hidden.
public struct MarkdownMarkerRange: Equatable {
    /// What the marker introduces — lets the renderer pick a replacement glyph
    /// (e.g. a real bullet for an unordered-list dash) instead of just hiding it.
    public enum Role: Equatable {
        case generic       // emphasis/code delimiters, leading `#␣`, `>`, fences
        case bullet        // unordered list marker (`- `, `* `, `+ `) → bullet glyph
    }

    public let location: Int
    public let length: Int
    public let role: Role

    public init(location: Int, length: Int, role: Role = .generic) {
        self.location = location
        self.length = length
        self.role = role
    }
}

// MARK: - Table structure

/// A GFM table extracted from the source, ready for grid rendering. The cell
/// strings are inline markdown (so the renderer can still bold/italic inside a
/// cell); `range` is the table's full source range so the editor can tell when
/// the caret is inside it (and fall back to raw pipe text for editing).
public struct MarkdownTableStructure: Equatable {
    public enum Alignment: Equatable {
        case leading
        case center
        case trailing
    }

    public let location: Int        // UTF-16 offset of the table start
    public let length: Int          // UTF-16 length of the whole table block
    public let headerCells: [String]
    public let bodyRows: [[String]]
    public let alignments: [Alignment]

    public init(
        location: Int,
        length: Int,
        headerCells: [String],
        bodyRows: [[String]],
        alignments: [Alignment]
    ) {
        self.location = location
        self.length = length
        self.headerCells = headerCells
        self.bodyRows = bodyRows
        self.alignments = alignments
    }

    public var columnCount: Int {
        max(headerCells.count, bodyRows.map(\.count).max() ?? 0)
    }
}

// MARK: - Analysis result

/// Everything the WYSIWYG editor needs from a single parse pass: styled spans,
/// concealable marker ranges, and table grids.
public struct MarkdownAnalysis: Equatable {
    public let spans: [MarkdownSyntaxSpan]
    public let markers: [MarkdownMarkerRange]
    public let tables: [MarkdownTableStructure]

    public init(
        spans: [MarkdownSyntaxSpan],
        markers: [MarkdownMarkerRange],
        tables: [MarkdownTableStructure]
    ) {
        self.spans = spans
        self.markers = markers
        self.tables = tables
    }

    public static let empty = MarkdownAnalysis(spans: [], markers: [], tables: [])
}

// MARK: - MarkdownSyntaxAnalyzer

public enum MarkdownSyntaxAnalyzer {
    /// Parses `source` and returns the spans that should be visually highlighted.
    /// Markers (``**``, `#`, `` ` ``, …) are preserved — this drives a live-edit
    /// highlighter, not a renderer.
    public static func spans(in source: String) -> [MarkdownSyntaxSpan] {
        analyze(source).spans
    }

    /// Full analysis for the WYSIWYG editor: spans + concealable markers + tables.
    public static func analyze(_ source: String) -> MarkdownAnalysis {
        guard !source.isEmpty else { return .empty }
        let document = Document(parsing: source, options: [.parseBlockDirectives])
        let mapper = SourceOffsetMapper(source: source)
        var collector = SpanCollector(mapper: mapper)
        collector.collect(document)
        return MarkdownAnalysis(
            spans: collector.spans,
            markers: collector.markers,
            tables: collector.tables
        )
    }
}

// MARK: - Span collection

private struct SpanCollector {
    let mapper: SourceOffsetMapper
    var spans: [MarkdownSyntaxSpan] = []
    var markers: [MarkdownMarkerRange] = []
    var tables: [MarkdownTableStructure] = []

    mutating func collect(_ markup: Markup) {
        // Tables own their whole subtree (rows/cells) — render as a grid, don't
        // descend into them for inline spans.
        if let table = markup as? Table {
            appendTable(table)
            return
        }
        appendSpan(for: markup)
        for child in markup.children {
            collect(child)
        }
    }

    private mutating func appendSpan(for markup: Markup) {
        switch markup {
        case let heading as Heading:
            add(heading.range, .heading(level: heading.level))
            addHeadingMarker(heading)
        case is Strong:
            add(markup.range, .bold)
            addDelimiterMarkers(markup.range, delimiter: "*", count: 2)
        case is Emphasis:
            add(markup.range, .italic)
            addEmphasisMarkers(markup.range)
        case is Strikethrough:
            add(markup.range, .strikethrough)
            addDelimiterMarkers(markup.range, delimiter: "~", count: 2)
        case is InlineCode:
            add(markup.range, .inlineCode)
            addInlineCodeMarkers(markup.range)
        case is CodeBlock:
            add(markup.range, .codeBlock)
        case is Link:
            add(markup.range, .link)
        case let quote as BlockQuote:
            add(markup.range, .blockQuote)
            addBlockQuoteMarkers(quote)
        case let item as ListItem:
            addListMarker(item)
        default:
            break
        }
    }

    private mutating func add(_ range: SourceRange?, _ kind: MarkdownSyntaxSpan.Kind) {
        guard let range, let span = mapper.span(for: range, kind: kind) else { return }
        spans.append(span)
    }

    private mutating func addMarker(
        location: Int, length: Int, role: MarkdownMarkerRange.Role = .generic
    ) {
        guard length > 0 else { return }
        markers.append(MarkdownMarkerRange(location: location, length: length, role: role))
    }

    // MARK: - Marker extraction

    /// Conceals the leading `#…#␣` of an ATX heading (content begins after it).
    private mutating func addHeadingMarker(_ heading: Heading) {
        guard let range = heading.range else { return }
        let start = mapper.utf16Offset(range.lowerBound)
        let end = mapper.utf16Offset(range.upperBound)
        guard let start, let end, end > start else { return }
        // Setext headings (underlined with === / ---) have no leading marker.
        let text = mapper.substring(from: start, to: end)
        guard text.first == "#" else { return }
        var i = text.startIndex
        var hashes = 0
        while i < text.endIndex, text[i] == "#" { hashes += 1; i = text.index(after: i) }
        // Include a single trailing space after the hashes, if present.
        var markerLen = hashes
        if i < text.endIndex, text[i] == " " { markerLen += 1 }
        addMarker(location: start, length: markerLen)
    }

    /// Conceals matching emphasis delimiters at both ends of `range`.
    private mutating func addDelimiterMarkers(
        _ range: SourceRange?, delimiter: Character, count: Int
    ) {
        guard let range else { return }
        let start = mapper.utf16Offset(range.lowerBound)
        let end = mapper.utf16Offset(range.upperBound)
        guard let start, let end, end - start >= count * 2 else { return }
        addMarker(location: start, length: count)
        addMarker(location: end - count, length: count)
    }

    /// Italic can be delimited by `*` or `_`, single run — detect from the source.
    private mutating func addEmphasisMarkers(_ range: SourceRange?) {
        guard let range else { return }
        let start = mapper.utf16Offset(range.lowerBound)
        let end = mapper.utf16Offset(range.upperBound)
        guard let start, let end, end > start else { return }
        let text = mapper.substring(from: start, to: end)
        guard let opener = text.first, opener == "*" || opener == "_",
              end - start >= 2 else { return }
        addMarker(location: start, length: 1)
        addMarker(location: end - 1, length: 1)
    }

    /// Inline code can use one or more backticks (`` `x` ``, ``` ``x`` ``` ).
    private mutating func addInlineCodeMarkers(_ range: SourceRange?) {
        guard let range else { return }
        let start = mapper.utf16Offset(range.lowerBound)
        let end = mapper.utf16Offset(range.upperBound)
        guard let start, let end, end > start else { return }
        let text = mapper.substring(from: start, to: end)
        var ticks = 0
        var i = text.startIndex
        while i < text.endIndex, text[i] == "`" { ticks += 1; i = text.index(after: i) }
        guard ticks > 0, end - start >= ticks * 2 else { return }
        addMarker(location: start, length: ticks)
        addMarker(location: end - ticks, length: ticks)
    }

    /// Conceals the leading `>␣` on each line of a block quote.
    private mutating func addBlockQuoteMarkers(_ quote: BlockQuote) {
        guard let range = quote.range else { return }
        let start = mapper.utf16Offset(range.lowerBound)
        let end = mapper.utf16Offset(range.upperBound)
        guard let start, let end, end > start else { return }
        let text = mapper.substring(from: start, to: end)
        var cursor = start
        for line in text.components(separatedBy: "\n") {
            // Skip any leading whitespace, then the `>` and one optional space.
            var idx = line.startIndex
            var lead = 0
            while idx < line.endIndex, line[idx] == " " { lead += 1; idx = line.index(after: idx) }
            if idx < line.endIndex, line[idx] == ">" {
                var markerLen = 1
                let afterGt = line.index(after: idx)
                if afterGt < line.endIndex, line[afterGt] == " " { markerLen += 1 }
                addMarker(location: cursor + lead, length: markerLen)
            }
            cursor += line.utf16.count + 1   // +1 for the consumed newline
        }
    }

    /// Conceals just the leading list marker (``- ``, ``* ``, ``1. ``) of a list
    /// item, and tags unordered markers so the renderer can swap in a bullet glyph.
    private mutating func addListMarker(_ item: ListItem) {
        guard let range = item.range else { return }
        let contentStart = item.child(at: 0)?.range?.lowerBound ?? range.upperBound
        guard let span = mapper.span(
            from: range.lowerBound, to: contentStart, kind: .listMarker
        ) else { return }
        spans.append(span)

        // Conceal the marker (everything up to the content). Tag `- / * / +` so the
        // renderer can render a bullet; ordered markers (`1.`) stay as-is.
        let markerText = mapper.substring(
            from: span.location, to: span.location + span.length
        )
        let trimmedLeading = markerText.drop(while: { $0 == " " })
        let role: MarkdownMarkerRange.Role =
            (trimmedLeading.first == "-" || trimmedLeading.first == "*" || trimmedLeading.first == "+")
            ? .bullet : .generic
        addMarker(location: span.location, length: span.length, role: role)
    }

    // MARK: - Tables

    private mutating func appendTable(_ table: Table) {
        guard let range = table.range else { return }
        let start = mapper.utf16Offset(range.lowerBound)
        let end = mapper.utf16Offset(range.upperBound)
        guard let start, let end, end > start else { return }

        let headerCells: [String] = Array(table.head.cells.map { Self.cellText($0) })
        let bodyRows: [[String]] = table.body.rows.map { row in
            Array(row.cells.map { Self.cellText($0) })
        }
        let alignments = table.columnAlignments.map { align -> MarkdownTableStructure.Alignment in
            switch align {
            case .some(.left):   return .leading
            case .some(.center): return .center
            case .some(.right):  return .trailing
            case .none:          return .leading
            }
        }

        tables.append(MarkdownTableStructure(
            location: start,
            length: end - start,
            headerCells: headerCells,
            bodyRows: bodyRows,
            alignments: alignments
        ))
    }

    private static func cellText(_ cell: Table.Cell) -> String {
        cell.plainText.trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - SourceLocation → UTF-16 mapping

/// Converts swift-markdown `SourceLocation`s (1-based line + UTF-8 byte column)
/// into UTF-16 offsets usable by `NSString`/`NSTextStorage`.
private struct SourceOffsetMapper {
    private let source: NSString
    private let utf16ForByte: [Int]   // byte offset → UTF-16 offset (size = utf8.count + 1)
    private let lineByteStart: [Int]  // 1-based; [0] unused
    private let totalBytes: Int

    init(source: String) {
        self.source = source as NSString
        let utf8Count = source.utf8.count
        var u16Map = [Int](repeating: 0, count: utf8Count + 1)
        var lineStarts: [Int] = [0, 0]  // index 0 unused; line 1 starts at byte 0
        var byte = 0
        var u16 = 0
        for scalar in source.unicodeScalars {
            let byteLen = String(scalar).utf8.count
            let utf16Len = scalar.value > 0xFFFF ? 2 : 1
            for k in 0..<byteLen { u16Map[byte + k] = u16 }
            byte += byteLen
            u16 += utf16Len
            if scalar == "\n" { lineStarts.append(byte) }
        }
        u16Map[utf8Count] = u16
        self.utf16ForByte = u16Map
        self.lineByteStart = lineStarts
        self.totalBytes = utf8Count
    }

    func span(
        for range: SourceRange,
        kind: MarkdownSyntaxSpan.Kind
    ) -> MarkdownSyntaxSpan? {
        span(from: range.lowerBound, to: range.upperBound, kind: kind)
    }

    func span(
        from lower: SourceLocation,
        to upper: SourceLocation,
        kind: MarkdownSyntaxSpan.Kind
    ) -> MarkdownSyntaxSpan? {
        guard let a = utf16Offset(line: lower.line, column: lower.column),
              let b = utf16Offset(line: upper.line, column: upper.column),
              b > a else { return nil }
        return MarkdownSyntaxSpan(location: a, length: b - a, kind: kind)
    }

    /// UTF-16 offset of a `SourceLocation`, or nil if it falls outside the source.
    func utf16Offset(_ location: SourceLocation) -> Int? {
        utf16Offset(line: location.line, column: location.column)
    }

    /// The source substring between two UTF-16 offsets (clamped to bounds).
    func substring(from: Int, to: Int) -> String {
        let len = source.length
        let lo = min(max(0, from), len)
        let hi = min(max(lo, to), len)
        return source.substring(with: NSRange(location: lo, length: hi - lo))
    }

    private func utf16Offset(line: Int, column: Int) -> Int? {
        guard line >= 1 else { return nil }
        let lineStartByte: Int
        if line < lineByteStart.count {
            lineStartByte = lineByteStart[line]
        } else if line == lineByteStart.count {
            lineStartByte = totalBytes
        } else {
            return nil
        }
        let byteOffset = min(max(0, lineStartByte + (column - 1)), totalBytes)
        return utf16ForByte[byteOffset]
    }
}
