import AppKit
import MarkdownEngine
import NoteTakrKit
import SwiftUI

/// NoteTakr's Markdown source editor, backed by MarkdownEngine's TextKit 2
/// live-preview editor. The binding remains the stored `note.md` Markdown.
struct NoteTakrMarkdownEditor: View {
    @Binding var text: String
    let documentId: String
    let theme: ThemeColors

    var body: some View {
        NativeTextViewWrapper(
            text: $text,
            configuration: configuration,
            fontName: "SF Pro",
            fontSize: 14,
            documentId: documentId,
            placeholder: placeholder
        )
    }

    private var configuration: MarkdownEditorConfiguration {
        var config = MarkdownEditorConfiguration.default
        config.theme = markdownTheme
        config.textInsets = TextInsets(horizontal: 16, vertical: 12)
        config.scrollers = .vertical
        config.paragraph = ParagraphStyle(spacingFactor: 0.22, lineHeightExtraSpacing: 3)
        config.headings = HeadingStyle(
            fontMultipliers: [1.70, 1.42, 1.22, 1.08, 1.0, 0.94],
            topSpacingEm: [0.24, 0.22, 0.18, 0.14, 0.10, 0.08]
        )
        config.overscroll = OverscrollPolicy(percent: 0.38, maxPoints: 320, minPoints: 56)
        config.markers = MarkerStyle(
            hiddenMarkerFontSize: 0.1,
            inlineCodeMarkerAlpha: 0.48,
            findMatchHighlightAlpha: 0.65
        )
        return config
    }

    private var markdownTheme: MarkdownEditorTheme {
        MarkdownEditorTheme(
            bodyText: theme.primaryText.nsColor,
            mutedText: theme.secondaryText.nsColor,
            disabledText: theme.secondaryText.nsColor.withAlphaComponent(0.55),
            headingMarker: theme.secondaryText.nsColor.withAlphaComponent(0.55),
            link: theme.accent.nsColor,
            incompleteLink: theme.accent.nsColor.withAlphaComponent(0.75),
            findMatchHighlight: theme.accent.nsColor.withAlphaComponent(0.22),
            findCurrentMatchHighlight: theme.accent.nsColor.withAlphaComponent(0.36),
            latexLightModeText: theme.primaryText.nsColor,
            latexDarkModeText: theme.primaryText.nsColor,
            strikethroughColor: theme.secondaryText.nsColor
        )
    }

    private var placeholder: NSAttributedString {
        NSAttributedString(
            string: "Start writing...",
            attributes: [
                .font: NSFont.systemFont(ofSize: 14),
                .foregroundColor: theme.secondaryText.nsColor.withAlphaComponent(0.55)
            ]
        )
    }
}
