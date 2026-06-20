import AppKit
import SwiftUI
import NoteTakrKit

// MARK: - MarkdownTextEditor

/// An always-editable, NSTextView-backed editor that renders markdown *live* as
/// you type — Obsidian "live preview" style. Markers (`#`, `**`, `_`, `` ` ``,
/// `>`, list bullets) are concealed so headings look big, bold looks bold and
/// code is monospaced, **without** ever removing the characters from the text
/// storage. The storage stays the real markdown source (`note.md`); only the
/// marker *glyphs* are hidden (see `ConcealingLayoutManager`).
///
/// Markers on the caret's current line are revealed for direct editing. GFM tables are
/// drawn as a real grid (`ConcealingLayoutManager`) unless the caret is inside the table,
/// in which case the raw pipe text is shown for editing.
///
/// Like before, it only replaces its string on *external* changes (note switch,
/// transcription regenerating `note.md`), so editing mid-text never resets the
/// caret to the end.
struct MarkdownTextEditor: NSViewRepresentable {
    @Binding var text: String
    var theme: ThemeColors
    var baseFontSize: CGFloat = 13.5

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        // Build a TextKit 1 stack explicitly so we can install our concealing
        // layout manager (NSTextView() may otherwise default to TextKit 2).
        let textStorage = NSTextStorage()
        let layoutManager = ConcealingLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(
            width: 0, height: CGFloat.greatestFiniteMagnitude
        ))
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)

        let textView = NSTextView(frame: .zero, textContainer: container)
        textView.delegate = context.coordinator
        layoutManager.delegate = context.coordinator
        textView.isRichText = false            // we apply our own attributes
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textContainerInset = NSSize(width: 12, height: 10)
        textView.font = NSFont.systemFont(ofSize: baseFontSize)
        textView.textColor = theme.primaryText.nsColor
        textView.insertionPointColor = theme.accent.nsColor

        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )

        textView.string = text
        context.coordinator.textView = textView
        context.coordinator.layoutManager = layoutManager
        context.coordinator.render(textView)

        let scroll = NSScrollView()
        scroll.documentView = textView
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        return scroll
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        let themeChanged = context.coordinator.theme != theme
        context.coordinator.parent = self
        context.coordinator.theme = theme

        // Only replace the string when it changed *outside* the editor (note switch,
        // transcription regenerating note.md, etc.). Typing never lands here because
        // the bound value converges to what's already in the text view.
        if textView.string != text {
            let selected = textView.selectedRange()
            textView.string = text
            let len = (text as NSString).length
            let loc = min(selected.location, len)
            textView.setSelectedRange(NSRange(location: loc, length: 0))
            textView.insertionPointColor = theme.accent.nsColor
            context.coordinator.render(textView)
        } else if themeChanged {
            textView.insertionPointColor = theme.accent.nsColor
            context.coordinator.render(textView)
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate, NSLayoutManagerDelegate {
        var parent: MarkdownTextEditor
        var theme: ThemeColors
        weak var textView: NSTextView?
        weak var layoutManager: ConcealingLayoutManager?

        /// Cached analysis from the last render, so `selectionDidChange` can
        /// recompute which markers to reveal without re-parsing.
        private var analysis: MarkdownAnalysis = .empty

        init(_ parent: MarkdownTextEditor) {
            self.parent = parent
            self.theme = parent.theme
        }

        // MARK: NSTextViewDelegate

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string   // push up; converges, so updateNSView no-ops
            render(textView)                 // attribute-only — does not move the caret
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            // Only the *concealment* depends on the caret position; re-applying it
            // is cheap and never touches the characters, so the caret stays put.
            applyConcealment(to: textView)
        }

        // MARK: Rendering

        /// Full pass: parse, apply visual attributes + table attachments, then
        /// concealment. Runs on edits / external string replacement / theme change.
        func render(_ textView: NSTextView) {
            guard let storage = textView.textStorage else { return }
            analysis = MarkdownSyntaxAnalyzer.analyze(storage.string)
            MarkdownLiveStyler.apply(
                to: storage,
                analysis: analysis,
                baseSize: parent.baseFontSize,
                theme: theme
            )
            // Keep typing attributes in sync so freshly typed text uses the base style.
            textView.typingAttributes = [
                .font: NSFont.systemFont(ofSize: parent.baseFontSize),
                .foregroundColor: theme.primaryText.nsColor
            ]
            applyConcealment(to: textView)
        }

        /// Recomputes which marker ranges to hide, revealing those on the caret's
        /// current line (and any table the caret is inside), then re-lays-out glyphs.
        private func applyConcealment(to textView: NSTextView) {
            guard let layoutManager else { return }
            let nsString = textView.string as NSString
            let caret = textView.selectedRange()
            let activeLine = nsString.lineRange(for: caret)

            var concealed: [NSRange] = []
            var bullets: [NSRange] = []

            for marker in analysis.markers {
                let range = NSRange(location: marker.location, length: marker.length)
                guard range.location >= 0, NSMaxRange(range) <= nsString.length else { continue }
                // Reveal markers on the active line so the user can edit the markdown
                // syntax directly without the caret jumping or the source changing.
                guard NSIntersectionRange(range, activeLine).length == 0 else { continue }
                switch marker.role {
                case .bullet: bullets.append(range)
                case .generic: concealed.append(range)
                }
            }

            // Tables: when the caret is outside, draw the grid (the pipe text is made
            // invisible and the separator line concealed to zero width); when inside,
            // show the raw pipe rows so the table is editable.
            let tableLayouts = buildTableLayouts(in: nsString, caret: caret)
            for layout in tableLayouts {
                concealed.append(layout.separatorRange)
            }
            applyTableTextVisibility(to: textView, layouts: tableLayouts)

            layoutManager.theme = theme
            layoutManager.baseFontSize = parent.baseFontSize
            layoutManager.setConcealment(
                concealed: concealed, bullets: bullets, tables: tableLayouts
            )
            invalidateGlyphs(layoutManager, length: nsString.length)
        }

        /// Builds a `TableLayout` for every table whose caret is *outside* it,
        /// splitting the table source into its header/body/separator lines.
        private func buildTableLayouts(in nsString: NSString, caret: NSRange) -> [TableLayout] {
            var layouts: [TableLayout] = []
            for table in analysis.tables {
                let range = NSRange(location: table.location, length: table.length)
                guard range.location >= 0, NSMaxRange(range) <= nsString.length, range.length > 0
                else { continue }
                let caretInside = NSIntersectionRange(range, caret).length > 0
                    || NSLocationInRange(caret.location, range)
                    || caret.location == NSMaxRange(range)
                guard !caretInside else { continue }

                // Source lines of the table: line 0 = header, line 1 = `|---|` separator,
                // lines 2… = body rows. Conceal the separator; the rest are grid rows.
                var lineRanges: [NSRange] = []
                var cursor = range.location
                while cursor < NSMaxRange(range) {
                    let lineRange = nsString.lineRange(for: NSRange(location: cursor, length: 0))
                    let clipped = NSIntersectionRange(lineRange, range)
                    if clipped.length > 0 { lineRanges.append(clipped) }
                    cursor = NSMaxRange(lineRange)
                }
                guard lineRanges.count >= 2 else { continue }
                let separator = lineRanges[1]
                let dataLines = [lineRanges[0]] + Array(lineRanges.dropFirst(2))

                layouts.append(TableLayout(
                    structure: table,
                    fullRange: range,
                    dataLineRanges: dataLines,
                    separatorRange: separator
                ))
            }
            return layouts
        }

        /// Makes the pipe text of grid-rendered tables invisible (clear foreground)
        /// while keeping it laid out so it reserves the grid's vertical space. Tables
        /// the caret just entered are restored to the primary colour so their raw pipe
        /// rows are editable. Attribute-only — never moves the caret.
        private func applyTableTextVisibility(to textView: NSTextView, layouts: [TableLayout]) {
            guard let storage = textView.textStorage else { return }
            let length = (storage.string as NSString).length
            guard length > 0 else { return }
            let nsString = storage.string as NSString
            storage.beginEditing()
            // First restore every table's text to primary (covers caret-entered case).
            for table in analysis.tables {
                let range = NSRange(location: table.location, length: table.length)
                guard range.location >= 0, NSMaxRange(range) <= nsString.length else { continue }
                storage.addAttribute(.foregroundColor, value: theme.primaryText.nsColor, range: range)
            }
            // Then hide the grid-rendered (caret-outside) tables' text.
            for layout in layouts {
                for line in layout.dataLineRanges {
                    storage.addAttribute(.foregroundColor, value: NSColor.clear, range: line)
                }
            }
            storage.endEditing()
        }

        private func invalidateGlyphs(_ layoutManager: NSLayoutManager, length: Int) {
            guard length > 0 else { return }
            let full = NSRange(location: 0, length: length)
            layoutManager.invalidateGlyphs(forCharacterRange: full,
                                           changeInLength: 0, actualCharacterRange: nil)
            layoutManager.invalidateLayout(forCharacterRange: full, actualCharacterRange: nil)
            layoutManager.ensureLayout(forCharacterRange: full)
        }
    }
}

// MARK: - MarkdownLiveStyler

/// Applies WYSIWYG visual attributes to a markdown text storage in place, driven
/// by `MarkdownSyntaxAnalyzer` (swift-markdown / cmark-gfm). Marker concealment is
/// handled separately by `ConcealingLayoutManager`; this only sets fonts/colours.
enum MarkdownLiveStyler {

    static func apply(
        to storage: NSTextStorage,
        analysis: MarkdownAnalysis,
        baseSize: CGFloat,
        theme: ThemeColors
    ) {
        let string = storage.string
        let full = NSRange(location: 0, length: (string as NSString).length)
        guard full.length > 0 else { return }

        let body = NSFont.systemFont(ofSize: baseSize)
        let primary = theme.primaryText.nsColor
        let secondary = theme.secondaryText.nsColor
        let accent = theme.accent.nsColor

        storage.beginEditing()
        defer { storage.endEditing() }

        // Reset to the plain body style, then layer parser-derived spans on top.
        storage.setAttributes([.font: body, .foregroundColor: primary], range: full)

        for span in analysis.spans {
            let range = NSRange(location: span.location, length: span.length)
            guard range.location >= 0, NSMaxRange(range) <= full.length else { continue }

            switch span.kind {
            case .heading(let level):
                let size = headingSize(level, base: baseSize)
                storage.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: size), range: range)
            case .bold:
                addTrait(.boldFontMask, to: storage, range: range, baseSize: baseSize)
            case .italic:
                addTrait(.italicFontMask, to: storage, range: range, baseSize: baseSize)
            case .strikethrough:
                storage.addAttribute(.strikethroughStyle,
                                     value: NSUnderlineStyle.single.rawValue, range: range)
                storage.addAttribute(.foregroundColor, value: secondary, range: range)
            case .inlineCode, .codeBlock:
                storage.addAttribute(.font, value: monoFont(baseSize), range: range)
                storage.addAttribute(.foregroundColor, value: accent, range: range)
            case .link:
                storage.addAttribute(.foregroundColor, value: accent, range: range)
            case .blockQuote:
                storage.addAttribute(.foregroundColor, value: secondary, range: range)
            case .listMarker:
                storage.addAttribute(.foregroundColor, value: accent, range: range)
            }
        }
    }

    // MARK: - Helpers

    private static func headingSize(_ level: Int, base: CGFloat) -> CGFloat {
        switch level {
        case 1:  return base + 8.5
        case 2:  return base + 5
        case 3:  return base + 2.5
        default: return base + 1
        }
    }

    private static func monoFont(_ size: CGFloat) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: size - 0.5, weight: .regular)
    }

    /// Adds bold/italic while preserving the existing font size (e.g. within a heading).
    private static func addTrait(
        _ trait: NSFontTraitMask,
        to storage: NSTextStorage,
        range: NSRange,
        baseSize: CGFloat
    ) {
        storage.enumerateAttribute(.font, in: range) { value, subRange, _ in
            let current = (value as? NSFont) ?? NSFont.systemFont(ofSize: baseSize)
            let converted = NSFontManager.shared.convert(current, toHaveTrait: trait)
            storage.addAttribute(.font, value: converted, range: subRange)
        }
    }
}
