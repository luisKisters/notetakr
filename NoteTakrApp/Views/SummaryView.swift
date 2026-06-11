import SwiftUI
import NoteTakrKit

struct SummaryView: View {
    let state: SummaryState
    let onGenerate: () -> Void
    @Environment(\.themeColors) private var theme

    var body: some View {
        switch state {
        case .missing:
            ScrollView {
                emptyStateContent
            }
        case .generating:
            ScrollView {
                generatingContent
            }
        case .ready(let text):
            MarkdownBodyView(parsed: MarkdownBodyParser.parse(text))
                .environment(\.themeColors, theme)
        case .failed(let message):
            ScrollView {
                failedContent(message)
            }
        }
    }

    // MARK: - States

    private var emptyStateContent: some View {
        VStack(spacing: 12) {
            Text("No summary yet. Generate one from the notes & transcript.")
                .font(.system(size: 12.5))
                .foregroundStyle(theme.secondaryText.swiftUIColor)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .frame(maxWidth: 240)
            generateButton(label: "Generate summary", isDisabled: false, spinning: false)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, 20)
    }

    private var generatingContent: some View {
        VStack {
            generateButton(label: "Generating…", isDisabled: true, spinning: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, 20)
    }

    private func failedContent(_ message: String) -> some View {
        VStack(spacing: 12) {
            Text(message)
                .font(.system(size: 12.5))
                .foregroundStyle(theme.destructive.swiftUIColor)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 240)
            generateButton(label: "Retry", isDisabled: false, spinning: false)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, 20)
    }

    // MARK: - Generate button (matches .genbtn in kit.css)

    private func generateButton(label: String, isDisabled: Bool, spinning: Bool) -> some View {
        Button(action: { if !isDisabled { onGenerate() } }) {
            HStack(spacing: 7) {
                if spinning {
                    SpinnerIcon()
                } else {
                    SparkleIcon()
                }
                Text(label)
                    .font(.system(size: 12.5, weight: .semibold))
            }
            .foregroundStyle(Color.white)
            .padding(.vertical, 9)
            .padding(.horizontal, 16)
            .background(isDisabled
                        ? theme.accent.swiftUIColor.opacity(0.6)
                        : theme.accent.swiftUIColor)
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .shadow(color: theme.accent.swiftUIColor.opacity(0.4), radius: 5, y: 2)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}

// MARK: - SF-style sparkle icon (matches kit.css .spark path)

private struct SparkleIcon: View {
    var body: some View {
        Canvas { ctx, _ in
            var path = Path()
            path.move(to: CGPoint(x: 8, y: 2.2))
            path.addLine(to: CGPoint(x: 9.5, y: 5.3))
            path.addLine(to: CGPoint(x: 12.9, y: 5.8))
            path.addLine(to: CGPoint(x: 10.45, y: 8.2))
            path.addLine(to: CGPoint(x: 11.03, y: 11.6))
            path.addLine(to: CGPoint(x: 8, y: 10.0))
            path.addLine(to: CGPoint(x: 4.97, y: 11.6))
            path.addLine(to: CGPoint(x: 5.55, y: 8.2))
            path.addLine(to: CGPoint(x: 3.1, y: 5.8))
            path.addLine(to: CGPoint(x: 6.5, y: 5.3))
            path.closeSubpath()
            ctx.stroke(path, with: .foreground,
                       style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
        }
        .frame(width: 14, height: 14)
    }
}

// MARK: - Spinner icon

private struct SpinnerIcon: View {
    @State private var rotation: Double = 0

    var body: some View {
        Canvas { ctx, _ in
            var path = Path()
            path.addArc(center: CGPoint(x: 8, y: 8), radius: 6,
                        startAngle: .degrees(-90), endAngle: .degrees(180), clockwise: false)
            ctx.stroke(path, with: .foreground,
                       style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
        }
        .frame(width: 14, height: 14)
        .rotationEffect(.degrees(rotation))
        .onAppear {
            withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
    }
}
