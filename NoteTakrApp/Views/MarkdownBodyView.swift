import SwiftUI
import NoteTakrKit

#if canImport(AppKit)
import AppKit

/// Renders a `ParsedMarkdownBody` as styled SwiftUI views matching `kit.css .md` rules.
/// ⌘C anywhere in this view writes `rawSource` to the pasteboard (not the rendered text).
struct MarkdownBodyView: View {
    let parsed: ParsedMarkdownBody
    @Environment(\.themeColors) private var theme

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(parsed.blocks.enumerated()), id: \.offset) { _, block in
                    blockView(block)
                }
                copyHint
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(
            Button("") { copyRawMarkdown() }
                .keyboardShortcut("c", modifiers: .command)
                .hidden()
        )
    }

    // MARK: - Block rendering

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            headingView(level: level, text: text)

        case .paragraph(let text):
            inlineView(text)
                .font(.system(size: 13.5))
                .lineSpacing(4)
                .padding(.vertical, 4)

        case .bulletItem(let text):
            HStack(alignment: .top, spacing: 0) {
                Text("•")
                    .font(.system(size: 13.5))
                    .foregroundStyle(theme.tertiaryText.swiftUIColor)
                    .frame(width: 17, alignment: .leading)
                    .padding(.leading, 3)
                inlineView(text)
                    .font(.system(size: 13.5))
                    .lineSpacing(3)
            }
            .padding(.vertical, 2)

        case .orderedItem(let index, let text):
            HStack(alignment: .top, spacing: 0) {
                Text("\(index).")
                    .font(.system(size: 13.5))
                    .foregroundStyle(theme.tertiaryText.swiftUIColor)
                    .frame(width: 22, alignment: .leading)
                    .padding(.leading, 2)
                inlineView(text)
                    .font(.system(size: 13.5))
                    .lineSpacing(3)
            }
            .padding(.vertical, 2)

        case .taskItem(let checked, let text):
            HStack(alignment: .top, spacing: 9) {
                taskCheckbox(checked: checked)
                    .padding(.top, 3.5)
                inlineView(text)
                    .font(.system(size: 13.5))
                    .lineSpacing(3)
                    .foregroundStyle(checked ? theme.tertiaryText.swiftUIColor
                                             : theme.primaryText.swiftUIColor)
                    .strikethrough(checked, color: theme.tertiaryText.swiftUIColor)
            }
            .padding(.vertical, 3.5)

        case .blockquote(let text):
            HStack(alignment: .top, spacing: 0) {
                Rectangle()
                    .fill(theme.hairline.swiftUIColor)
                    .frame(width: 2)
                    .padding(.trailing, 11)
                inlineView(text)
                    .font(.system(size: 13.5))
                    .lineSpacing(3)
                    .foregroundStyle(theme.secondaryText.swiftUIColor)
            }
            .padding(.vertical, 4)

        case .codeBlock(let code, _):
            Text(code)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(theme.primaryText.swiftUIColor)
                .padding(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.codeBg.swiftUIColor)
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .padding(.vertical, 5)

        case .horizontalRule:
            Rectangle()
                .fill(theme.hairline.swiftUIColor)
                .frame(height: 1)
                .padding(.vertical, 8)
        }
    }

    // MARK: - Heading views (kit.css .md h1/h2/h3+)

    @ViewBuilder
    private func headingView(level: Int, text: String) -> some View {
        switch level {
        case 1:
            Text(text)
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(theme.primaryText.swiftUIColor)
                .tracking(-0.2)
                .padding(.top, 18)
                .padding(.bottom, 8)
        case 2:
            Text(text)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(theme.primaryText.swiftUIColor)
                .padding(.top, 18)
                .padding(.bottom, 7)
        case 3:
            Text(text)
                .font(.system(size: 13.5, weight: .bold))
                .foregroundStyle(theme.secondaryText.swiftUIColor)
                .padding(.top, 14)
                .padding(.bottom, 5)
        default:
            Text(text)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.secondaryText.swiftUIColor)
                .padding(.top, 12)
                .padding(.bottom, 4)
        }
    }

    // MARK: - Inline content (handles **bold**, *italic*, `code` via AttributedString markdown)

    @ViewBuilder
    private func inlineView(_ raw: String) -> some View {
        if let attr = try? AttributedString(
            markdown: raw,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            Text(attr)
                .foregroundStyle(theme.primaryText.swiftUIColor)
        } else {
            Text(raw)
                .foregroundStyle(theme.primaryText.swiftUIColor)
        }
    }

    // MARK: - Task checkbox

    @ViewBuilder
    private func taskCheckbox(checked: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4.5)
                .fill(checked ? theme.accent.swiftUIColor : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 4.5)
                        .stroke(
                            checked ? theme.accent.swiftUIColor : theme.tertiaryText.swiftUIColor,
                            lineWidth: 1.5
                        )
                )
            if checked {
                Path { p in
                    p.move(to: CGPoint(x: 2.5, y: 7.5))
                    p.addLine(to: CGPoint(x: 5.5, y: 10.5))
                    p.addLine(to: CGPoint(x: 12.5, y: 3.5))
                }
                .stroke(Color.white, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(width: 15, height: 15)
    }

    // MARK: - Copy hint

    private var copyHint: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 10.5, weight: .light))
                .foregroundStyle(theme.tertiaryText.swiftUIColor)
            Text("Select & copy")
                .font(.system(size: 10.5))
                .foregroundStyle(theme.tertiaryText.swiftUIColor)
            kbdPill("⌘A")
            kbdPill("⌘C")
            Text("→ raw markdown")
                .font(.system(size: 10.5))
                .foregroundStyle(theme.tertiaryText.swiftUIColor)
        }
        .padding(.top, 12)
    }

    private func kbdPill(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundStyle(theme.secondaryText.swiftUIColor)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(theme.kbdBackground.swiftUIColor)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(theme.kbdBorder.swiftUIColor, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    // MARK: - Clipboard

    private func copyRawMarkdown() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(parsed.rawSource, forType: .string)
    }
}
#endif
