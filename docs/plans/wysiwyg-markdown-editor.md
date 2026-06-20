# Plan: WYSIWYG markdown editor (Agent 1)

Goal: the Notes tab editor should look rendered while staying editable — markers
(`#`, `**`, `_`, `` ` ``, `>`, list bullets) concealed; headings bigger/bold; bold/italic/
code styled; **GFM tables rendered as a real grid**. Markers for the line containing the
caret are revealed so they can be edited (Obsidian live-preview style). No caret jumping.

## Owned files (do NOT edit anything else)
- `NoteTakrApp/Views/MarkdownTextEditor.swift`
- `NoteTakrApp/Views/EditorView.swift` (only the `.privateNotes` tab branch)
- `NoteTakrKit/Sources/NoteTakrKit/MarkdownSyntaxAnalyzer.swift`
- Any NEW app file you add (e.g. a custom `NSLayoutManager`) — and then `Notetakr.xcodeproj/project.pbxproj` to register it (4 entries: PBXBuildFile, PBXFileReference, group children, Sources phase — copy the existing `MarkdownTextEditor.swift` entries as a template; IDs look like `AAFADE00000000000000XXXX`).
- You MAY add to `NoteTakrApp/Views/MarkdownBodyView.swift` / `MarkdownBodyParser.swift` only if you reuse them; otherwise leave them.

Do NOT touch `NotePanelController.swift`, `RecordPillStateMachine.swift`, `AppModel.swift`, switcher files, `NoteStore.swift`, or `Package.swift`.

## Approach
- `swift-markdown` is already a Kit dependency. Extend `MarkdownSyntaxAnalyzer` to also return:
  - the **marker sub-ranges** to conceal (e.g. the `**` pairs, the leading `#␣`, backticks, `>`, list-marker that should become a bullet glyph), separate from the styled content ranges.
  - **table structure** (rows × cells with column alignment + the table's full source range) so the editor can render a grid.
- In `MarkdownTextEditor` (NSViewRepresentable over NSTextView):
  - Conceal markers using an `NSLayoutManager` subclass that returns `.null` glyph properties for concealed character ranges (in `layoutManager(_:shouldGenerateGlyphs:...)`), so markers take zero width but stay in the text storage / `note.md`. Reveal (don't conceal) the markers whose paragraph/line contains the current selection; re-layout on selection change.
  - Apply visual attributes for headings (size by level, bold), bold, italic, inline code (mono), block quote (muted), list bullets.
  - Render tables with `NSTextTable` / `NSTextTableBlock` paragraph styles so NSTextView draws real grid lines. When the caret enters a table's source range, fall back to showing that block's raw pipe text (so it's editable); re-render the grid when the caret leaves.
  - Keep the existing cursor-safety rule: only replace `textView.string` in `updateNSView` when it differs from the binding (never on self-edits).
- Use context7 (`ctx7`) for any TextKit / `NSLayoutManager` / `NSTextTable` API you're unsure about.

## Checklist
- [x] Extend `MarkdownSyntaxAnalyzer` to emit marker ranges + table structure (keep existing `spans` API working).
- [x] Add an `NSLayoutManager` subclass that conceals marker ranges via `.null` glyphs.
- [x] Wire concealment into `MarkdownTextEditor`; reveal markers on the caret's current line; re-layout on `selectionDidChange`.
- [x] Style headings (size by level), bold, italic, inline code, block quote, list bullets.
- [x] Render GFM tables as a real grid; show raw pipes only when caret is inside the table.
  - Implemented via a custom-drawn grid in `ConcealingLayoutManager.drawGlyphs` (the pipe text is laid out but made invisible; the separator row is concealed to zero width). `NSTextTable`/attachment proved intractable because attachments require the U+FFFC object-replacement char, which would corrupt the `note.md` markdown source; custom grid drawing keeps the storage byte-for-byte raw markdown.
- [x] Preserve cursor stability (no jump when editing earlier text); plain typing still works. Kept the "only replace `textView.string` when it differs from the binding" rule; concealment/visibility are attribute-only or glyph-property-only and never mutate characters.
- [x] `cd NoteTakrKit && swift build` passes (validates the analyzer). Do NOT run the full xcodebuild.
- [x] Update this checklist (check every box) as you finish each item.

## Acceptance
Typing `# Title`, `**bold**`, `` `code` ``, and a `| a | b |` table: title shows large with no `#`, bold shows bold with no `**`, table shows as a grid. Moving the caret onto a heading line reveals its `#` for editing. No caret reset when editing mid-document.
