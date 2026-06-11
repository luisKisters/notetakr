import AppKit
import SwiftUI
import NoteTakrCore
import NoteTakrKit

// MARK: - Language options

private let languageOptions: [(value: String, label: String)] = [
    ("auto", "Auto-detect (recommended)"),
    ("en", "English"),
    ("de", "German"),
    ("fr", "French"),
    ("es", "Spanish"),
    ("it", "Italian"),
    ("pt", "Portuguese"),
    ("zh", "Chinese"),
    ("ja", "Japanese"),
    ("ko", "Korean"),
]

// MARK: - SettingsSheetView

struct SettingsSheetView: View {
    @ObservedObject var viewModel: SettingsSheetViewModel
    @StateObject private var permissions = AudioPermissionManager()
    @StateObject private var vocab = VocabularyViewModel()
    @State private var modelSettings: TranscriptionModelSettings = .default
    private let transcriptionSettingsStore = TranscriptionSettingsStore()
    @State private var newPerMeetingTerm: String = ""

    private let sheetBg = Color(red: 0.110, green: 0.102, blue: 0.128)
    private let hairline = Color.white.opacity(0.08)
    private let accent = Color(red: 0.545, green: 0.361, blue: 0.965)
    private let textPrimary = Color(red: 0.937, green: 0.929, blue: 0.952)
    private let textSecondary = Color(red: 0.659, green: 0.643, blue: 0.702)
    private let textTertiary = Color(red: 0.471, green: 0.455, blue: 0.486)
    private let controlBg = Color.white.opacity(0.09)

    var body: some View {
        ZStack(alignment: .bottom) {
            // Dim the note behind
            Color.black.opacity(0.26)
                .ignoresSafeArea()
                .onTapGesture { viewModel.close() }

            // The sheet
            VStack(spacing: 0) {
                tabBar

                if viewModel.showScopeBanner {
                    scopeBanner
                }

                Divider()
                    .background(hairline)
                    .opacity(0)

                scrollBody

                footerBar
            }
            .frame(maxWidth: .infinity)
            .frame(height: 527) // ~85% of 620
            .background(sheetBg)
            .clipShape(
                .rect(
                    topLeadingRadius: 16,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 16
                )
            )
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.12))
                    .frame(height: 1)
                    .frame(maxWidth: .infinity)
                    .offset(y: 0)
                    .clipShape(.rect(topLeadingRadius: 16, bottomLeadingRadius: 0,
                                    bottomTrailingRadius: 0, topTrailingRadius: 16))
            }
            .shadow(color: .black.opacity(0.45), radius: 24, y: -8)
        }
        // Esc key closes the sheet without closing the panel
        .background(
            Button("") { viewModel.close() }
                .keyboardShortcut(.escape, modifiers: [])
                .hidden()
        )
        .onAppear {
            permissions.refresh(includeCalendar: true)
            vocab.reload()
            modelSettings = transcriptionSettingsStore.load()
        }
    }

    // MARK: - Tab bar

    private var tabBar: some View {
        HStack(spacing: 2) {
            tabButton(.thisMeeting, icon: "calendar.badge.checkmark", label: "This Meeting")
            tabButton(.general,     icon: "gearshape",               label: "General")
            tabButton(.recording,   icon: "waveform",                 label: "Recording")
            tabButton(.vocabulary,  icon: "book.closed",              label: "Vocabulary")
            tabButton(.permissions, icon: "checkmark.shield",         label: "Permissions")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(sheetBg)
    }

    private func tabButton(_ tab: SettingsTab, icon: String, label: String) -> some View {
        let isActive = viewModel.selectedTab == tab
        return Button {
            viewModel.selectedTab = tab
        } label: {
            VStack(spacing: 3.5) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .light))
                Text(label)
                    .font(.system(size: 9.5, weight: isActive ? .semibold : .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .foregroundColor(isActive ? accent : textSecondary)
            .background(isActive ? accent.opacity(0.12) : Color.clear)
            .cornerRadius(9)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Scope banner

    private var scopeBanner: some View {
        HStack(spacing: 7) {
            Image(systemName: "calendar")
                .font(.system(size: 11, weight: .light))
                .foregroundColor(accent.opacity(0.9))

            Group {
                Text(viewModel.noteTitle).fontWeight(.semibold)
                + Text(" — these settings apply only to this note")
            }
            .font(.system(size: 11))
            .foregroundColor(textSecondary)
            .lineLimit(2)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(accent.opacity(0.05))
        .overlay(alignment: .bottom) {
            Rectangle().fill(hairline).frame(height: 1)
        }
    }

    // MARK: - Scrollable body

    private var scrollBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                switch viewModel.selectedTab {
                case .thisMeeting:  thisMeetingContent
                case .general:      generalContent
                case .recording:    recordingContent
                case .vocabulary:   vocabularyContent
                case .permissions:  permissionsContent
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - This Meeting content

    private var thisMeetingContent: some View {
        Group {
            sectionLabel("Transcription")

            settingsRow {
                Image(systemName: "waveform")
                    .iconStyle()
                VStack(alignment: .leading, spacing: 2) {
                    Text("Transcribe this meeting").font(.system(size: 13)).foregroundColor(textPrimary)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { viewModel.frontmatterBridge.noteTranscribe ?? viewModel.appSettings.transcribeByDefault },
                    set: { viewModel.setTranscribeThisMeeting($0) }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .tint(accent)
            }

            settingsRow {
                Image(systemName: "globe")
                    .iconStyle()
                Text("Language").font(.system(size: 13)).foregroundColor(textPrimary)
                Spacer()
                Picker("", selection: Binding(
                    get: { viewModel.frontmatterBridge.noteLanguage?.rawValue ?? "auto" },
                    set: { viewModel.setLanguageThisMeeting(TranscribeLanguage(rawValue: $0)) }
                )) {
                    ForEach(languageOptions, id: \.value) { opt in
                        Text(opt.label).tag(opt.value)
                    }
                }
                .pickerStyle(.menu)
                .font(.system(size: 12))
                .frame(maxWidth: 180)
            }

            settingsRow {
                Image(systemName: "person.fill")
                    .iconStyle()
                VStack(alignment: .leading, spacing: 2) {
                    Text("In-person meeting").font(.system(size: 13)).foregroundColor(textPrimary)
                    Text("Mic only — skips system audio")
                        .font(.system(size: 11)).foregroundColor(textTertiary)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { viewModel.frontmatterBridge.presenter?.note.inPerson ?? viewModel.appSettings.inPersonByDefault },
                    set: { viewModel.setInPersonThisMeeting($0) }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .tint(accent)
            }

            sectionLabel("Calendar")

            settingsRow {
                Image(systemName: "link")
                    .iconStyle()
                VStack(alignment: .leading, spacing: 2) {
                    Text("Linked calendar event").font(.system(size: 13)).foregroundColor(textPrimary)
                    if let event = viewModel.frontmatterBridge.noteCalendarEvent {
                        Text(event).font(.system(size: 11)).foregroundColor(textTertiary).lineLimit(1)
                    } else {
                        Text("None").font(.system(size: 11)).foregroundColor(textTertiary)
                    }
                }
                Spacer()
                if viewModel.frontmatterBridge.noteCalendarEvent != nil {
                    Button("Unlink") { viewModel.unlinkEvent() }
                        .buttonStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundColor(textTertiary)
                }
            }

            sectionLabel("Vocabulary for this meeting")

            VStack(alignment: .leading, spacing: 9) {
                Text("Boosted in recognition for this note only — global terms still apply.")
                    .font(.system(size: 11))
                    .foregroundColor(textTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                FlowLayout(spacing: 6) {
                    ForEach(viewModel.frontmatterBridge.noteVocabulary, id: \.self) { term in
                        vocabChip(term)
                    }
                    TextField("Add phrase…", text: $newPerMeetingTerm)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11.5))
                        .foregroundColor(textPrimary)
                        .frame(minWidth: 80)
                        .onSubmit {
                            guard !newPerMeetingTerm.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                            viewModel.addVocabularyTermThisMeeting(newPerMeetingTerm.trimmingCharacters(in: .whitespaces))
                            newPerMeetingTerm = ""
                        }
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 2)
        }
    }

    private func vocabChip(_ term: String) -> some View {
        HStack(spacing: 5) {
            Text(term).font(.system(size: 11.5))
            Button {
                viewModel.removeVocabularyTermThisMeeting(term)
            } label: {
                Text("×").font(.system(size: 11))
            }
            .buttonStyle(.plain)
        }
        .foregroundColor(accent.opacity(0.9))
        .padding(.horizontal, 9)
        .padding(.vertical, 2)
        .background(accent.opacity(0.13))
        .overlay(Capsule().stroke(accent.opacity(0.3), lineWidth: 1))
        .clipShape(Capsule())
    }

    // MARK: - General content

    private var generalContent: some View {
        Group {
            sectionLabel("Defaults for new meetings")

            settingsRow {
                Image(systemName: "waveform")
                    .iconStyle()
                VStack(alignment: .leading, spacing: 2) {
                    Text("Transcribe meetings").font(.system(size: 13)).foregroundColor(textPrimary)
                    Text("Every new meeting starts transcribing")
                        .font(.system(size: 11)).foregroundColor(textTertiary)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { viewModel.appSettings.transcribeByDefault },
                    set: { viewModel.setTranscribeByDefault($0) }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .tint(accent)
            }

            VStack(alignment: .leading, spacing: 7) {
                settingsRow {
                    Image(systemName: "globe")
                        .iconStyle()
                    Text("Transcription language").font(.system(size: 13)).foregroundColor(textPrimary)
                    Spacer()
                    Picker("", selection: Binding(
                        get: { viewModel.appSettings.defaultLanguage.rawValue },
                        set: { viewModel.setDefaultLanguage(TranscribeLanguage(rawValue: $0)) }
                    )) {
                        ForEach(languageOptions, id: \.value) { opt in
                            Text(opt.label).tag(opt.value)
                        }
                    }
                    .pickerStyle(.menu)
                    .font(.system(size: 12))
                    .frame(maxWidth: 180)
                }

                if viewModel.showLanguageWarning {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(Color.orange.opacity(0.78))
                        Text(EffectiveMeetingSettings.languageWarningText)
                            .font(.system(size: 11))
                            .foregroundColor(Color.orange.opacity(0.78))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.leading, 25)
                    .padding(.bottom, 4)
                }
            }
            .padding(.bottom, 2)

            settingsRow {
                Image(systemName: "person.fill")
                    .iconStyle()
                VStack(alignment: .leading, spacing: 2) {
                    Text("In-person meeting").font(.system(size: 13)).foregroundColor(textPrimary)
                    Text("Mic only — skips system audio")
                        .font(.system(size: 11)).foregroundColor(textTertiary)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { viewModel.appSettings.inPersonByDefault },
                    set: { viewModel.setInPersonByDefault($0) }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .tint(accent)
            }

            sectionLabel("App")

            settingsRow {
                Image(systemName: "keyboard")
                    .iconStyle()
                Text("Global hotkey").font(.system(size: 13)).foregroundColor(textPrimary)
                Spacer()
                HotkeyRecorderView(
                    combo: viewModel.appSettings.hotkey,
                    onComboChange: { viewModel.setHotkey($0) }
                )
                .frame(width: 110, height: 26)
            }

            settingsRow {
                Image(systemName: "power")
                    .iconStyle()
                Text("Launch at login").font(.system(size: 13)).foregroundColor(textPrimary)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { viewModel.appSettings.launchAtLogin },
                    set: { viewModel.setLaunchAtLogin($0) }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .tint(accent)
            }

            settingsRow {
                Image(systemName: "circle.lefthalf.filled")
                    .iconStyle()
                Text("Appearance").font(.system(size: 13)).foregroundColor(textPrimary)
                Spacer()
                Picker("", selection: Binding(
                    get: { viewModel.currentAppearance },
                    set: { viewModel.setAppearance($0) }
                )) {
                    Text("Glass").tag(Appearance.glass)
                    Text("Dark").tag(Appearance.dark)
                    Text("Light").tag(Appearance.light)
                }
                .pickerStyle(.segmented)
                .frame(width: 152)
            }

            settingsRow {
                Image(systemName: "folder")
                    .iconStyle()
                VStack(alignment: .leading, spacing: 2) {
                    Text("Notes folder").font(.system(size: 13)).foregroundColor(textPrimary)
                    Text(viewModel.appSettings.notesFolderPath ?? "~/Library/Application Support/NoteTakr")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundColor(textSecondary)
                        .lineLimit(1)
                }
                Spacer()
                Button("Change\u{2026}") { selectNotesFolder() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundColor(textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(controlBg)
                    .cornerRadius(6.5)
                    .overlay(RoundedRectangle(cornerRadius: 6.5)
                        .stroke(Color.white.opacity(0.15), lineWidth: 0.5))
            }
        }
    }

    // MARK: - Recording content

    private var recordingContent: some View {
        Group {
            sectionLabel("Engine")

            settingsRow {
                Image(systemName: "cpu")
                    .iconStyle()
                VStack(alignment: .leading, spacing: 2) {
                    Text("Model").font(.system(size: 13)).foregroundColor(textPrimary)
                    Text("Runs fully on-device")
                        .font(.system(size: 11)).foregroundColor(textTertiary)
                }
                Spacer()
                Picker("", selection: Binding(
                    get: { modelSettings.modelVersion },
                    set: { modelSettings.modelVersion = $0; persistModelSettings() }
                )) {
                    ForEach(FluidAudioModelVersion.allCases, id: \.self) { v in
                        Text(v.displayName).tag(v)
                    }
                }
                .pickerStyle(.menu)
                .font(.system(size: 12))
            }

            HStack(spacing: 8) {
                Button("Select Folder\u{2026}") { selectModelFolder() }
                    .controlSize(.small)
                Button("Use Auto") { updateModelSettings(source: .fluidAudioDefaultCache) }
                    .controlSize(.small)
                Button("Clear") { updateModelSettings(source: .notConfigured) }
                    .controlSize(.small)
                    .disabled(modelSettings.source == .notConfigured)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 2)
        }
    }

    // MARK: - Vocabulary content

    private var vocabularyContent: some View {
        Group {
            sectionLabel("Global vocabulary")

            Text("Names & jargon boosted in every meeting. Per-meeting terms live on the This Meeting tab.")
                .font(.system(size: 11))
                .foregroundColor(textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 2)
                .padding(.bottom, 8)

            ForEach(vocab.entries) { entry in
                HStack(spacing: 10) {
                    Image(systemName: entry.isEnabled ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(entry.isEnabled ? .green : textTertiary)
                        .onTapGesture { vocab.toggle(entry) }
                    Text(entry.phrase)
                        .font(.system(size: 13))
                        .foregroundColor(textPrimary)
                    Spacer()
                    Text("×\(String(format: "%.1f", entry.boostingWeight))")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(textTertiary)
                    Button {
                        if let idx = vocab.entries.firstIndex(where: { $0.id == entry.id }) {
                            vocab.remove(at: IndexSet([idx]))
                        }
                    } label: {
                        Image(systemName: "xmark").font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(textTertiary)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 2)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(hairline).frame(height: 1)
                }
            }

            vocabAddRow
        }
    }

    @State private var newVocabPhrase: String = ""

    private var vocabAddRow: some View {
        HStack(spacing: 8) {
            TextField("Add phrase\u{2026}", text: $newVocabPhrase)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundColor(textPrimary)
                .onSubmit { submitVocabPhrase() }
            Button("Add") { submitVocabPhrase() }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(accent)
                .disabled(newVocabPhrase.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 2)
    }

    // MARK: - Permissions content

    private var permissionsContent: some View {
        Group {
            sectionLabel("Permissions")

            permRow(
                label: "Microphone",
                detail: "Required for transcription",
                status: permissions.microphoneStatus,
                action: { Task { await permissions.requestMicrophoneAccess() } }
            )

            permRow(
                label: "Calendar",
                detail: "Links notes to events",
                status: permissions.calendarStatus,
                action: { Task { await permissions.requestCalendarAccess() } }
            )

            systemAudioRow

            Text("macOS may ask again after updates. NoteTakr never sends audio off this Mac.")
                .font(.system(size: 11))
                .foregroundColor(textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
                .padding(.horizontal, 2)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissions.refresh()
        }
    }

    @ViewBuilder
    private func permRow(label: String, detail: String, status: PermissionStatus, action: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(statusColor(status))
                .frame(width: 8, height: 8)
                .shadow(color: statusColor(status).opacity(0.6), radius: 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.system(size: 13)).foregroundColor(textPrimary)
                Text(detail).font(.system(size: 11)).foregroundColor(textTertiary)
            }
            Spacer()
            if status != .granted {
                Button("Grant") { action() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundColor(textTertiary)
            } else {
                Text("Granted ✓")
                    .font(.system(size: 12))
                    .foregroundColor(.green)
            }
        }
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) { Rectangle().fill(hairline).frame(height: 1) }
    }

    private var systemAudioRow: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(permissions.systemAudioStatus == .granted ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
                .shadow(color: (permissions.systemAudioStatus == .granted ? Color.green : Color.orange).opacity(0.6), radius: 4)
            VStack(alignment: .leading, spacing: 2) {
                Text("System Audio").font(.system(size: 13)).foregroundColor(textPrimary)
                Text(permissions.systemAudioRestartRequired ? "Restart required" : "Other participants in calls")
                    .font(.system(size: 11))
                    .foregroundColor(permissions.systemAudioRestartRequired ? .orange : textTertiary)
            }
            Spacer()
            if permissions.systemAudioStatus != .granted {
                Button(permissions.systemAudioRestartRequired ? "Restart" : "Grant") {
                    if permissions.systemAudioRestartRequired {
                        permissions.restartApp()
                    } else {
                        permissions.requestSystemAudioAccess()
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(textTertiary)
            }
        }
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) { Rectangle().fill(hairline).frame(height: 1) }
    }

    private func statusColor(_ status: PermissionStatus) -> Color {
        switch status {
        case .granted: return .green
        case .denied: return .red
        case .notDetermined: return .orange
        }
    }

    // MARK: - Footer

    private var footerBar: some View {
        VStack(spacing: 0) {
            Rectangle().fill(hairline).frame(height: 1)
            HStack {
                Spacer()
                Button {
                    viewModel.close()
                } label: {
                    HStack(spacing: 8) {
                        Text("Close")
                            .font(.system(size: 12))
                            .foregroundColor(textSecondary)
                        Text("⎋ esc")
                            .font(.system(size: 10))
                            .foregroundColor(textTertiary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(controlBg)
                            .cornerRadius(4.5)
                            .overlay(RoundedRectangle(cornerRadius: 4.5)
                                .stroke(Color.white.opacity(0.15), lineWidth: 0.5))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 3.5)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settingsCloseButton")
                Spacer()
            }
            .frame(height: 36)
        }
    }

    // MARK: - Shared row builder

    @ViewBuilder
    private func settingsRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 10) {
            content()
        }
        .frame(minHeight: 42)
        .padding(.vertical, 0)
        .overlay(alignment: .bottom) {
            Rectangle().fill(hairline).frame(height: 1)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundColor(textTertiary)
            .tracking(0.7)
            .padding(.top, 16)
            .padding(.bottom, 2)
            .padding(.horizontal, 2)
    }

    // MARK: - Helpers

    private func submitVocabPhrase() {
        let trimmed = newVocabPhrase.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        vocab.add(phrase: trimmed)
        newVocabPhrase = ""
    }

    private func selectNotesFolder() {
        let panel = NSOpenPanel()
        panel.title = "Select Notes Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            viewModel.appSettings.notesFolderPath = url.path
        }
    }

    private func selectModelFolder() {
        let panel = NSOpenPanel()
        panel.title = "Select FluidAudio Model Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            updateModelSettings(source: .localFolder(url))
        }
    }

    private func updateModelSettings(source: TranscriptionModelSettings.Source) {
        modelSettings.source = source
        persistModelSettings()
    }

    private func persistModelSettings() {
        try? transcriptionSettingsStore.save(modelSettings)
    }
}

// MARK: - Simple FlowLayout for vocabulary chips

private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 300
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Icon style modifier

private extension Image {
    func iconStyle() -> some View {
        self.font(.system(size: 14, weight: .light))
            .frame(width: 15, height: 15)
            .foregroundColor(Color.white.opacity(0.4))
    }
}

// MARK: - HotkeyRecorderView

/// Editable hotkey recorder backed by a custom NSControl.
/// Shows the current combo; click to enter recording mode; press modifier+key to save.
private struct HotkeyRecorderView: NSViewRepresentable {
    let combo: HotkeyCombo
    let onComboChange: (HotkeyCombo) -> Void

    func makeNSView(context: Context) -> HotkeyRecorderControl {
        let control = HotkeyRecorderControl()
        control.displayCombo = combo
        control.onComboChange = onComboChange
        return control
    }

    func updateNSView(_ control: HotkeyRecorderControl, context: Context) {
        if !control.isRecording {
            control.displayCombo = combo
        }
    }
}

/// NSControl that renders a hotkey pill and captures key events when focused.
final class HotkeyRecorderControl: NSControl {
    var displayCombo: HotkeyCombo? {
        didSet { if !isRecording { refreshLabel() } }
    }
    var onComboChange: ((HotkeyCombo) -> Void)?
    private(set) var isRecording = false

    private let label = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        configure()
    }
    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }

    private func configure() {
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.white.withAlphaComponent(0.15).cgColor
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.09).cgColor

        label.isBezeled = false
        label.isEditable = false
        label.drawsBackground = false
        label.alignment = .center
        label.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        label.textColor = NSColor.labelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(clicked)))
        refreshLabel()
    }

    @objc private func clicked() {
        window?.makeFirstResponder(self)
        startRecording()
    }

    private func startRecording() {
        isRecording = true
        label.stringValue = "Press shortcut\u{2026}"
        label.textColor = NSColor.secondaryLabelColor
        layer?.borderColor = NSColor.controlAccentColor.cgColor
    }

    private func stopRecording() {
        isRecording = false
        layer?.borderColor = NSColor.white.withAlphaComponent(0.15).cgColor
        refreshLabel()
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { super.keyDown(with: event); return }

        var mods = HotkeyCombo.Modifiers()
        let flags = event.modifierFlags
        if flags.contains(.command) { mods.insert(.command) }
        if flags.contains(.option)  { mods.insert(.option) }
        if flags.contains(.shift)   { mods.insert(.shift) }
        if flags.contains(.control) { mods.insert(.control) }

        let chars = (event.charactersIgnoringModifiers ?? "").uppercased()
        guard let keyChar = chars.first,
              let combo = try? HotkeyCombo(modifiers: mods, key: keyChar) else {
            stopRecording()
            return
        }

        onComboChange?(combo)
        stopRecording()
    }

    override func resignFirstResponder() -> Bool {
        if isRecording { stopRecording() }
        return super.resignFirstResponder()
    }

    private func refreshLabel() {
        label.stringValue = displayCombo?.displayString ?? "None"
        label.textColor = NSColor.labelColor
    }
}
