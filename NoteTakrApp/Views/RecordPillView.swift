import SwiftUI
import NoteTakrKit

// MARK: - RecordPillView

/// Monochrome record pill matching kit.css .recpill.
/// Only the indicator dot carries color: gray (idle), red (recording), amber (paused).
/// Width stays fixed by using tabular-nums + a reserved-width label.
struct RecordPillView: View {
    let machine: RecordPillStateMachine
    let pillState: RecordPillState
    @Environment(\.themeColors) private var theme

    @State private var dotPhase = false
    @State private var isHovering = false

    private var isMenuShowing: Bool {
        if case .showingMenu = pillState { return true }
        return false
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            pillButton
            if case .showingMenu = pillState {
                recordMenu
                    .offset(y: 28)
                    .zIndex(100)
                    .transition(
                        .opacity.combined(with: .scale(scale: 0.94, anchor: .topLeading))
                        .animation(.spring(response: 0.22, dampingFraction: 0.80))
                    )
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isMenuShowing)
    }

    // MARK: - Pill button

    private var pillButton: some View {
        Button {
            machine.tap()
        } label: {
            HStack(spacing: 6) {
                indicatorDot
                pillLabel
            }
            .frame(height: 23)
            .padding(.horizontal, 10)
        }
        .buttonStyle(PillButtonStyle(theme: theme, isHovering: isHovering))
        .onHover { isHovering = $0 }
    }

    // MARK: - Indicator dot

    private var indicatorDot: some View {
        let color: Color
        let animate: Bool

        switch pillState {
        case .idle:
            color = theme.tertiaryText.swiftUIColor
            animate = false
        case .recording:
            color = theme.destructive.swiftUIColor
            animate = true
        case .paused, .showingMenu:
            color = DesignConstants.pauseAmber.swiftUIColor
            animate = true
        }

        return Circle()
            .fill(color)
            .frame(width: 7, height: 7)
            .opacity(animate ? (dotPhase ? 1.0 : 0.2) : 1.0)
            .animation(
                animate
                    ? .easeInOut(duration: dotAnimDuration).repeatForever(autoreverses: true)
                    : .none,
                value: dotPhase
            )
            .onAppear {
                if animate { dotPhase = true }
            }
            .onChange(of: pillState) { newState in
                switch newState {
                case .recording, .paused, .showingMenu:
                    dotPhase = true
                case .idle:
                    dotPhase = false
                }
            }
    }

    private var dotAnimDuration: Double {
        switch pillState {
        case .recording: return 0.8
        case .paused, .showingMenu: return 0.75
        default: return 0.8
        }
    }

    // MARK: - Label

    private var pillLabel: some View {
        Text(labelText)
            .font(.system(size: 11.5, design: .monospaced).monospacedDigit())
            .foregroundStyle(theme.primaryText.swiftUIColor)
    }

    private var labelText: String {
        switch pillState {
        case .idle:
            return "Record"
        case .recording(let elapsed), .paused(let elapsed), .showingMenu(let elapsed):
            return FrontmatterPresenter.formatElapsed(TimeInterval(elapsed))
        }
    }

    // MARK: - Pop-up menu

    private var recordMenu: some View {
        VStack(alignment: .leading, spacing: 0) {
            menuButton(icon: "play.fill", label: "Resume") {
                machine.menuResume()
            }
            Divider()
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
            menuButton(icon: "stop.fill", label: "Stop & Transcribe") {
                machine.menuStopAndTranscribe()
            }
            menuButton(icon: "sparkles", label: "Stop & Summarize") {
                machine.menuStopAndSummarize()
            }
        }
        .padding(.vertical, 5)
        .frame(minWidth: 180)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(theme.panelFill.swiftUIColor.opacity(10))
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.regularMaterial)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(theme.hairline.swiftUIColor, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.28), radius: 12, x: 0, y: 6)
        .compositingGroup()
    }

    private func menuButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.tertiaryText.swiftUIColor)
                    .frame(width: 13, height: 13)
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.primaryText.swiftUIColor)
                Spacer()
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color.clear)
                .padding(.horizontal, 4)
        )
        .padding(.horizontal, 4)
    }
}

// MARK: - PillButtonStyle

private struct PillButtonStyle: ButtonStyle {
    let theme: ThemeColors
    let isHovering: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 999)
                    .fill(isHovering
                          ? theme.chipFillHover.swiftUIColor
                          : theme.chipFill.swiftUIColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 999)
                    .stroke(theme.chipLine.swiftUIColor, lineWidth: 1)
            )
            .animation(.easeInOut(duration: 0.15), value: isHovering)
    }
}
