import SwiftUI
import NoteTakrKit

// MARK: - RecordPillView

/// Split-badge recording control matching recording-final.html.
///
/// States with a caret: recording, paused — caret shows per-state menu.
/// States without a caret: idle, transcribing, summarizing, done, doneTranscript.
///
/// Tap semantics:
///   idle            → start
///   recording       → stop & summarize
///   paused          → resume
///   done/doneTranscript → view tab
///   transcribing/summarizing → no-op (busy)
struct RecordPillView: View {
    let machine: RecordPillStateMachine
    let pillState: RecordPillState
    let onIdleTapOverride: (() -> Void)?
    @Environment(\.themeColors) private var theme

    @State private var mainHovering = false
    @State private var caretHovering = false
    @State private var menuOpen = false

    init(
        machine: RecordPillStateMachine,
        pillState: RecordPillState,
        onIdleTapOverride: (() -> Void)? = nil
    ) {
        self.machine = machine
        self.pillState = pillState
        self.onIdleTapOverride = onIdleTapOverride
    }

    private var hasCaret: Bool {
        if case .recording = pillState { return true }
        if case .paused = pillState { return true }
        return false
    }

    private var isBusy: Bool {
        if case .transcribing = pillState { return true }
        if case .summarizing = pillState { return true }
        return false
    }

    var body: some View {
        badge
            .contentShape(Capsule())
    }

    // MARK: - Badge shell

    private var badge: some View {
        HStack(spacing: 0) {
            mainButton
            if hasCaret {
                Divider()
                    .frame(width: 1, height: 16)
                    .overlay(theme.hairline.swiftUIColor)
                caretButton
            }
        }
        .frame(height: 26)
        .background(
            RoundedRectangle(cornerRadius: 999)
                .fill(theme.chipFill.swiftUIColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 999)
                .stroke(theme.chipLine.swiftUIColor, lineWidth: 1)
        )
    }

    // MARK: - Main button

    private var mainButton: some View {
        Button {
            guard !isBusy else { return }
            menuOpen = false
            if pillState == .idle {
                if let onIdleTapOverride {
                    onIdleTapOverride()
                } else {
                    machine.requestStart()
                }
            } else {
                machine.tap()
            }
        } label: {
            HStack(spacing: 7) {
                indicatorDot
                mainLabel
            }
            .padding(.leading, 11)
            .padding(.trailing, hasCaret ? 9 : 11)
            .frame(minWidth: hasCaret ? 72 : 78)
            .frame(height: 26)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            Group {
                if mainHovering && !isBusy {
                    if hasCaret {
                        UnevenRoundedRectangle(
                            topLeadingRadius: 999,
                            bottomLeadingRadius: 999,
                            bottomTrailingRadius: 3,
                            topTrailingRadius: 3
                        )
                        .fill(theme.hoverFill.swiftUIColor)
                    } else {
                        RoundedRectangle(cornerRadius: 999)
                            .fill(theme.hoverFill.swiftUIColor)
                    }
                }
            }
        )
        .onHover { mainHovering = $0 }
        .contentShape(Rectangle())
        .accessibilityIdentifier("recordPillMainButton")
    }

    // MARK: - Caret button

    private var caretButton: some View {
        Button {
            menuOpen.toggle()
        } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(caretHovering
                                 ? theme.primaryText.swiftUIColor
                                 : theme.secondaryText.swiftUIColor)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            Group {
                if caretHovering {
                    UnevenRoundedRectangle(
                        topLeadingRadius: 3,
                        bottomLeadingRadius: 3,
                        bottomTrailingRadius: 999,
                        topTrailingRadius: 999
                    )
                    .fill(theme.hoverFill.swiftUIColor)
                }
            }
        )
        .onHover { caretHovering = $0 }
        .contentShape(Rectangle())
        .accessibilityIdentifier("recordPillCaretButton")
        .popover(isPresented: $menuOpen, arrowEdge: .bottom) {
            caretMenuContent
                .environment(\.themeColors, theme)
        }
    }

    // MARK: - Indicator dot

    private var indicatorDot: some View {
        let (color, showRing) = dotAppearance
        return ZStack {
            if showRing {
                Circle()
                    .fill(color.opacity(0.2))
                    .frame(width: 13, height: 13)
            }
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
        }
    }

    /// Dot colour + whether to draw the faint idle ring. (No pulsing.)
    private var dotAppearance: (Color, Bool) {
        switch pillState {
        case .idle:
            return (DesignConstants.recRed.swiftUIColor, true)
        case .recording:
            return (DesignConstants.recRed.swiftUIColor, false)
        case .paused:
            return (DesignConstants.pauseAmber.swiftUIColor, false)
        case .transcribing, .summarizing:
            return (DesignConstants.statusGreen.swiftUIColor, false)
        case .done, .doneTranscript:
            return (DesignConstants.statusGreen.swiftUIColor, false)
        }
    }

    // MARK: - Main label

    private var mainLabel: some View {
        Group {
            switch pillState {
            case .idle:
                Text("Record")
            case .recording(let elapsed):
                Text(FrontmatterPresenter.formatElapsed(TimeInterval(elapsed)))
            case .paused(let elapsed):
                HStack(spacing: 4) {
                    Text("Paused")
                    Text(FrontmatterPresenter.formatElapsed(TimeInterval(elapsed)))
                        .opacity(0.55)
                }
            case .transcribing:
                Text("Transcribing…")
            case .summarizing:
                Text("Summarizing…")
            case .done:
                HStack(spacing: 3) {
                    Text("Summarized")
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(theme.accent.swiftUIColor)
                }
            case .doneTranscript:
                HStack(spacing: 3) {
                    Text("Transcribed")
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(theme.accent.swiftUIColor)
                }
            }
        }
        .font(.system(size: 11.5, weight: .medium).monospacedDigit())
        .foregroundStyle(theme.primaryText.swiftUIColor)
    }

    // MARK: - Caret menu (popover content)
    // Background, border, and shadow come from the system popover container.
    // ESC is handled natively by the popover; onExitCommand is an extra safeguard.

    @ViewBuilder
    private var caretMenuContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch pillState {
            case .recording:
                menuItem(icon: "pause.fill", label: "Pause") {
                    menuOpen = false; machine.menuPause()
                }
                menuSeparator
                menuItem(icon: "stop.fill", label: "Stop without summarizing") {
                    menuOpen = false; machine.menuStopOnly()
                }
                menuItem(icon: "arrow.clockwise", label: "Restart recording") {
                    menuOpen = false; machine.menuRestart()
                }
                menuSeparator
                menuItem(icon: "trash", label: "Discard recording", danger: true) {
                    menuOpen = false; machine.menuDiscard()
                }
            case .paused:
                menuItem(icon: "sparkles", label: "Stop & summarize") {
                    menuOpen = false; machine.menuStopAndSummarize()
                }
                menuItem(icon: "stop.fill", label: "Stop without summarizing") {
                    menuOpen = false; machine.menuStopOnly()
                }
                menuItem(icon: "arrow.clockwise", label: "Restart recording") {
                    menuOpen = false; machine.menuRestart()
                }
                menuSeparator
                menuItem(icon: "trash", label: "Discard recording", danger: true) {
                    menuOpen = false; machine.menuDiscard()
                }
            default:
                EmptyView()
            }
        }
        .padding(.vertical, 5)
        .frame(minWidth: 210)
        .onExitCommand { menuOpen = false }
    }

    private var menuSeparator: some View {
        Divider()
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
    }

    private func menuItem(
        icon: String,
        label: String,
        danger: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(danger ? DesignConstants.recRed.swiftUIColor : theme.tertiaryText.swiftUIColor)
                    .frame(width: 13, height: 13)
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(danger ? DesignConstants.recRed.swiftUIColor : theme.primaryText.swiftUIColor)
                Spacer()
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
    }
}
