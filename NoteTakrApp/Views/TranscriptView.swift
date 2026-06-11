import SwiftUI
import NoteTakrKit

struct TranscriptView: View {
    let state: TranscriptState
    var speakerResolutions: [String: SpeakerResolution] = [:]

    @Environment(\.themeColors) private var theme
    @State private var collapsedIndices: Set<Int> = []
    @State private var nameOverrides: [String: String] = [:]
    @State private var showCopyToast = false
    @State private var copyToastTask: Task<Void, Never>?

    private var segments: [DisplaySegment] {
        if case .segments(let segs) = state { return segs }
        return []
    }

    var body: some View {
        VStack(spacing: 0) {
            if segments.isEmpty {
                emptyView
            } else {
                toolbar
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        let indexMap = speakerIndexMap
                        ForEach(Array(segments.enumerated()), id: \.offset) { idx, seg in
                            TurnRow(
                                index: idx,
                                segment: seg,
                                speakerIndex: indexMap[seg.speaker] ?? 0,
                                resolution: speakerResolutions[seg.speaker ?? ""],
                                nameOverride: nameOverrides[seg.speaker ?? ""],
                                isCollapsed: collapsedIndices.contains(idx),
                                isLast: idx == segments.count - 1,
                                theme: theme,
                                onToggleCollapse: { collapsedIndices.formSymmetricDifference([idx]) },
                                onRename: { newName in applyRename(speakerID: seg.speaker, newName: newName) }
                            )
                        }
                    }
                    .padding(.horizontal, 2)
                }
                .onCopyCommand {
                    let md = TranscriptMerger.copyAsMarkdown(
                        turns: segments,
                        speakerResolutions: speakerResolutions,
                        nameOverrides: nameOverrides
                    )
                    showCopyToastBriefly()
                    return [NSItemProvider(object: md as NSString)]
                }
            }
        }
        .overlay(alignment: .bottom) {
            if showCopyToast {
                toastView
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .padding(.bottom, 54)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showCopyToast)
    }

    // MARK: - Empty state

    private var emptyView: some View {
        Text("No transcript yet.")
            .font(.system(size: 14))
            .foregroundStyle(theme.tertiaryText.swiftUIColor)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 40)
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            miniButton("Collapse all") { collapsedIndices = Set(0..<segments.count) }
            miniButton("Expand all") { collapsedIndices = [] }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .padding(.bottom, 10)
    }

    private func miniButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(theme.secondaryText.swiftUIColor)
                .padding(.vertical, 4)
                .padding(.horizontal, 9)
                .background(theme.chipFill.swiftUIColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(theme.chipLine.swiftUIColor, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Toast

    private var toastView: some View {
        Text("Copied as markdown")
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(Color.white)
            .padding(.vertical, 7)
            .padding(.horizontal, 13)
            .background(theme.accent.swiftUIColor)
            .clipShape(Capsule())
            .shadow(color: theme.accent.swiftUIColor.opacity(0.5), radius: 10, y: 3)
    }

    // MARK: - Helpers

    private var speakerIndexMap: [String?: Int] {
        var seen: [String?: Int] = [:]
        var next = 0
        for seg in segments {
            if seen[seg.speaker] == nil {
                seen[seg.speaker] = next
                next += 1
            }
        }
        return seen
    }

    private func applyRename(speakerID: String?, newName: String) {
        guard let id = speakerID else { return }
        nameOverrides[id] = newName
    }

    private func showCopyToastBriefly() {
        showCopyToast = true
        copyToastTask?.cancel()
        copyToastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            guard !Task.isCancelled else { return }
            showCopyToast = false
        }
    }
}

// MARK: - TurnRow

private struct TurnRow: View {
    let index: Int
    let segment: DisplaySegment
    let speakerIndex: Int
    let resolution: SpeakerResolution?
    let nameOverride: String?
    let isCollapsed: Bool
    let isLast: Bool
    let theme: ThemeColors
    let onToggleCollapse: () -> Void
    let onRename: (String) -> Void

    private static let avatarColors: [RGBA] = [
        RGBA(red: 139, green: 92, blue: 246),  // purple
        RGBA(red: 25, green: 160, blue: 140),   // teal
        RGBA(red: 255, green: 159, blue: 10),   // amber
        RGBA(red: 52, green: 199, blue: 89),    // green
    ]

    private var avatarColor: Color {
        let base = Self.avatarColors[speakerIndex % Self.avatarColors.count]
        return Color(red: base.r, green: base.g, blue: base.b).opacity(0.85)
    }

    private var avatarInitial: String {
        if let override = nameOverride { return String(override.prefix(1)).uppercased() }
        switch resolution {
        case .confirmed(let n): return String(n.prefix(1)).uppercased()
        case .uncertain(let g): return String(g.prefix(1)).uppercased()
        case nil: return String((segment.speaker ?? "?").prefix(1)).uppercased()
        }
    }

    private var previewText: String {
        let t = segment.text
        return t.count > 52 ? String(t.prefix(52)) + "\u{2026}" : t
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row — tap toggles collapse (speaker name tap handled inside SpeakerNameCell)
            headerRow
                .contentShape(Rectangle())
                .onTapGesture { onToggleCollapse() }

            // Body — hidden when collapsed
            if !isCollapsed {
                Text(segment.text)
                    .font(.system(size: 13.5))
                    .foregroundStyle(theme.primaryText.swiftUIColor.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 32)
                    .padding(.trailing, 4)
                    .padding(.top, 3)
                    .padding(.bottom, 6)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle()
                    .fill(theme.hairline.swiftUIColor)
                    .frame(height: 1)
            }
        }
    }

    private var headerRow: some View {
        HStack(spacing: 7) {
            // Avatar circle
            ZStack {
                Circle()
                    .fill(avatarColor)
                Text(avatarInitial)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.white)
            }
            .frame(width: 22, height: 22)

            // Speaker name (renameable) — tap is captured here, not propagated to collapse
            SpeakerNameCell(
                speaker: segment.speaker,
                resolution: resolution,
                nameOverride: nameOverride,
                theme: theme,
                onRename: onRename
            )

            // Preview (collapsed only)
            if isCollapsed {
                Text(previewText)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.secondaryText.swiftUIColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 4)

            // Timestamp
            Text(segment.startStamp)
                .font(.system(size: 11))
                .foregroundStyle(theme.tertiaryText.swiftUIColor)

            // Collapse chevron
            Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(theme.tertiaryText.swiftUIColor)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
    }
}

// MARK: - SpeakerNameCell

private struct SpeakerNameCell: View {
    let speaker: String?
    let resolution: SpeakerResolution?
    let nameOverride: String?
    let theme: ThemeColors
    let onRename: (String) -> Void

    @State private var isRenaming = false
    @State private var renameText = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        Group {
            if isRenaming {
                TextField("", text: $renameText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(theme.primaryText.swiftUIColor)
                    .frame(width: 130)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(theme.fieldFill.swiftUIColor)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(theme.accent.swiftUIColor, lineWidth: 1)
                            )
                    )
                    .focused($isFocused)
                    .onSubmit { commit(keep: true) }
                    .onChange(of: isFocused) { focused in
                        if !focused { commit(keep: true) }
                    }
                    .task { isFocused = true }
            } else {
                Button {
                    renameText = currentDisplayName
                    isRenaming = true
                } label: {
                    speakerLabel
                }
                .buttonStyle(.plain)
            }
        }
        .onTapGesture {
            // Captured by button or TextField — prevents propagation to collapse toggle
        }
    }

    @ViewBuilder
    private var speakerLabel: some View {
        if let override = nameOverride {
            Text(override)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(theme.primaryText.swiftUIColor)
        } else {
            switch resolution {
            case .confirmed(let name):
                Text(name)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(theme.primaryText.swiftUIColor)
            case .uncertain(let guess):
                (Text("Speaker \u{00B7} ").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(theme.primaryText.swiftUIColor) +
                 Text("most likely \(guess)").font(.system(size: 12, weight: .medium)).foregroundStyle(theme.secondaryText.swiftUIColor))
            case nil:
                Text(speaker ?? "Unknown")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(theme.primaryText.swiftUIColor)
            }
        }
    }

    private var currentDisplayName: String {
        if let override = nameOverride { return override }
        switch resolution {
        case .confirmed(let n): return n
        case .uncertain(let g): return g
        case nil: return speaker ?? ""
        }
    }

    private func commit(keep: Bool) {
        guard isRenaming else { return }
        isRenaming = false
        isFocused = false
        let trimmed = renameText.trimmingCharacters(in: .whitespaces)
        if keep, !trimmed.isEmpty {
            onRename(trimmed)
        }
    }
}
