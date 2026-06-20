import AppKit
import NoteTakrKit

// MARK: - TableLayout

/// A GFM table to draw as a grid plus the source ranges needed to lay it out.
/// `dataLineRanges` are the header + body source lines (one grid row each);
/// `separatorRange` is the `|:--|--:|` line, which is concealed to zero width so
/// it reserves no vertical space and the grid maps cleanly onto the kept lines.
struct TableLayout {
    let structure: MarkdownTableStructure
    let fullRange: NSRange
    let dataLineRanges: [NSRange]
    let separatorRange: NSRange
}

// MARK: - ConcealingLayoutManager

/// A TextKit 1 layout manager that hides marker glyphs (``**``, leading `#␣`,
/// backticks, `>`, list bullets) without removing the characters from the text
/// storage — so the markdown source in `note.md` is untouched while the editor
/// *looks* rendered (Obsidian live-preview style).
///
/// Concealment works by returning the ``NSLayoutManager/GlyphProperty/null``
/// property for the concealed character ranges in `setGlyphs(…)`, which lays them
/// out with zero advancement. Unordered-list markers are replaced with a real
/// bullet glyph. GFM tables are drawn as a real grid in `drawGlyphs(…)` while their
/// pipe text is rendered invisible (clear foreground) by the styler.
final class ConcealingLayoutManager: NSLayoutManager {

    /// Character ranges whose glyphs should be hidden entirely (zero width).
    private(set) var concealedRanges: [NSRange] = []
    /// Character ranges (the `- ` / `* ` of a bullet) drawn as a single bullet glyph.
    private(set) var bulletMarkerRanges: [NSRange] = []
    /// Tables to paint as a grid (only those whose caret is outside, set by the editor).
    private(set) var tableLayouts: [TableLayout] = []

    /// Theme + size for grid drawing, supplied by the editor each render.
    var theme: ThemeColors?
    var baseFontSize: CGFloat = 13.5

    func setConcealment(
        concealed: [NSRange],
        bullets: [NSRange],
        tables: [TableLayout]
    ) {
        concealedRanges = concealed
        bulletMarkerRanges = bullets
        tableLayouts = tables
    }

    // MARK: - Glyph concealment

    /// Does `characterIndex` fall inside any concealed (zero-width) range?
    private func isHidden(_ characterIndex: Int) -> Bool {
        for range in concealedRanges where NSLocationInRange(characterIndex, range) {
            return true
        }
        return false
    }

    /// If `characterIndex` is the first character of a bullet marker, return true.
    private func isBulletHead(_ characterIndex: Int) -> Bool {
        for range in bulletMarkerRanges where range.location == characterIndex {
            return true
        }
        return false
    }

    /// Is `characterIndex` inside a bullet marker but not its first character?
    private func isBulletTail(_ characterIndex: Int) -> Bool {
        for range in bulletMarkerRanges
        where NSLocationInRange(characterIndex, range) && range.location != characterIndex {
            return true
        }
        return false
    }

    override func setGlyphs(
        _ glyphs: UnsafePointer<CGGlyph>,
        properties props: UnsafePointer<NSLayoutManager.GlyphProperty>,
        characterIndexes charIndexes: UnsafePointer<Int>,
        font aFont: NSFont,
        forGlyphRange glyphRange: NSRange
    ) {
        guard !concealedRanges.isEmpty || !bulletMarkerRanges.isEmpty else {
            super.setGlyphs(glyphs, properties: props, characterIndexes: charIndexes,
                            font: aFont, forGlyphRange: glyphRange)
            return
        }

        let count = glyphRange.length
        var newGlyphs = [CGGlyph](repeating: 0, count: count)
        var newProps = [NSLayoutManager.GlyphProperty](repeating: .null, count: count)
        let bulletGlyph = bulletCGGlyph(for: aFont)

        for i in 0..<count {
            let charIndex = charIndexes[i]
            if let bulletGlyph, isBulletHead(charIndex) {
                // First char of an unordered marker → draw a bullet glyph instead.
                newGlyphs[i] = bulletGlyph
                newProps[i] = props[i]
            } else if isBulletTail(charIndex) || isHidden(charIndex) {
                // Hidden (zero-width): trailing chars of a bullet marker, or any
                // concealed marker like `**`, `#␣`, backticks, `>`, table separator.
                newGlyphs[i] = glyphs[i]
                newProps[i] = .null
            } else {
                newGlyphs[i] = glyphs[i]
                newProps[i] = props[i]
            }
        }

        newGlyphs.withUnsafeBufferPointer { gp in
            newProps.withUnsafeBufferPointer { pp in
                super.setGlyphs(gp.baseAddress!, properties: pp.baseAddress!,
                                characterIndexes: charIndexes, font: aFont,
                                forGlyphRange: glyphRange)
            }
        }
    }

    /// The CGGlyph for "•" in `font`, or nil if the font can't render it.
    private func bulletCGGlyph(for font: NSFont) -> CGGlyph? {
        var unichar: [UniChar] = Array("•".utf16)
        var glyphs = [CGGlyph](repeating: 0, count: unichar.count)
        let ok = CTFontGetGlyphsForCharacters(font as CTFont, &unichar, &glyphs, unichar.count)
        return ok ? glyphs.first : nil
    }

    // MARK: - Grid drawing

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
        guard !tableLayouts.isEmpty, let container = textContainers.first else { return }

        for table in tableLayouts {
            // Collect the rect of each kept (header/body) data line.
            var rowRects: [NSRect] = []
            for lineRange in table.dataLineRanges {
                let gr = glyphRange(forCharacterRange: lineRange, actualCharacterRange: nil)
                guard gr.length > 0 else { continue }
                var rect = boundingRect(forGlyphRange: gr, in: container)
                rect.origin.x += origin.x
                rect.origin.y += origin.y
                rowRects.append(rect)
            }
            guard !rowRects.isEmpty else { continue }
            drawGrid(table.structure, rowRects: rowRects)
        }
    }

    private func drawGrid(_ table: MarkdownTableStructure, rowRects: [NSRect]) {
        guard let theme else { return }
        let columns = max(1, table.columnCount)
        let rows: [[String]] = [table.headerCells] + table.bodyRows
        guard rowRects.count >= rows.count, rows.count >= 1 else { return }

        // Grid spans from the left inset to a sensible right edge; size columns to
        // their content but never exceed the available line width.
        let left = rowRects.map(\.minX).min() ?? 0
        let availableWidth = (rowRects.map(\.maxX).max() ?? left) - left
        let top = rowRects.map(\.minY).min() ?? 0
        let bottom = rowRects.map(\.maxY).max() ?? top

        let columnWidths = computeColumnWidths(
            rows: rows, columns: columns, available: availableWidth
        )
        let gridWidth = columnWidths.reduce(0, +)

        let hairline = theme.hairline.nsColor
        let headerFill = theme.codeBg.nsColor
        let primary = theme.primaryText.nsColor
        let padX: CGFloat = 6

        // Header background (first row band).
        let headerHeight = rowRects[0].height
        headerFill.setFill()
        NSRect(x: left, y: top, width: gridWidth, height: headerHeight).fill()

        // Outer + inner borders.
        hairline.setStroke()
        let grid = NSBezierPath()
        grid.lineWidth = 1

        // Horizontal lines: top of each row + final bottom.
        for rect in rowRects {
            let y = rect.minY
            grid.move(to: NSPoint(x: left, y: y))
            grid.line(to: NSPoint(x: left + gridWidth, y: y))
        }
        grid.move(to: NSPoint(x: left, y: bottom))
        grid.line(to: NSPoint(x: left + gridWidth, y: bottom))

        // Vertical lines.
        var x = left
        grid.move(to: NSPoint(x: x, y: top))
        grid.line(to: NSPoint(x: x, y: bottom))
        for col in 0..<columns {
            x += columnWidths[col]
            grid.move(to: NSPoint(x: x, y: top))
            grid.line(to: NSPoint(x: x, y: bottom))
        }
        grid.stroke()

        // Cell text.
        for (rowIdx, row) in rows.enumerated() {
            let rect = rowRects[rowIdx]
            let isHeader = rowIdx == 0
            let f = isHeader
                ? NSFont.boldSystemFont(ofSize: baseFontSize)
                : NSFont.systemFont(ofSize: baseFontSize)
            let attrs: [NSAttributedString.Key: Any] = [.font: f, .foregroundColor: primary]
            var cellX = left
            for col in 0..<columns {
                let text = col < row.count ? row[col] : ""
                let columnWidth = columnWidths[col]
                let alignment = col < table.alignments.count ? table.alignments[col] : .leading
                let textSize = (text as NSString).size(withAttributes: attrs)

                let textX: CGFloat
                switch alignment {
                case .leading:  textX = cellX + padX
                case .center:   textX = cellX + (columnWidth - textSize.width) / 2
                case .trailing: textX = cellX + columnWidth - padX - textSize.width
                }
                let textY = rect.minY + (rect.height - textSize.height) / 2
                (text as NSString).draw(at: NSPoint(x: textX, y: textY), withAttributes: attrs)
                cellX += columnWidth
            }
        }
    }

    /// Column widths sized to content (with padding), scaled down to fit `available`.
    private func computeColumnWidths(
        rows: [[String]], columns: Int, available: CGFloat
    ) -> [CGFloat] {
        let padX: CGFloat = 6
        var widths = [CGFloat](repeating: 0, count: columns)
        for (rowIdx, row) in rows.enumerated() {
            let f = rowIdx == 0
                ? NSFont.boldSystemFont(ofSize: baseFontSize)
                : NSFont.systemFont(ofSize: baseFontSize)
            for col in 0..<columns {
                let text = col < row.count ? row[col] : ""
                let w = (text as NSString).size(withAttributes: [.font: f]).width
                widths[col] = max(widths[col], ceil(w) + padX * 2)
            }
        }
        let total = widths.reduce(0, +)
        if total > available, total > 0 {
            let scale = available / total
            widths = widths.map { $0 * scale }
        }
        return widths
    }
}
