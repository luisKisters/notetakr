import AppKit
import SwiftUI
import NoteTakrCore
import NoteTakrKit

// MARK: - Language options

private let languageOptions: [(value: String, label: String)] = [
    ("auto", "Auto-detect"),
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
    @Environment(\.themeColors) private var theme
    @StateObject private var permissions = AudioPermissionManager()
    @StateObject private var vocab = VocabularyViewModel()
    @StateObject private var summarization = SummarizationViewModel()
    @State private var modelSettings: TranscriptionModelSettings = .default
    private let transcriptionSettingsStore = TranscriptionSettingsStore()
    @State private var newPerMeetingTerm: String = ""
    @State private var yourNameDraft: String = ""

    private var hairline: Color { theme.hairline.swiftUIColor }
    private var accent: Color { theme.accent.swiftUIColor }
    private var textPrimary: Color { theme.primaryText.swiftUIColor }
    private var textSecondary: Color { theme.secondaryText.swiftUIColor }
    private var textTertiary: Color { theme.tertiaryText.swiftUIColor }
    private var controlBg: Color { theme.elevatedFill.swiftUIColor }

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
            .background {
                ThemedSurface(appearance: viewModel.currentAppearance)
            }
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
                    .fill(hairline)
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
            summarization.reload()
            modelSettings = transcriptionSettingsStore.load()
            yourNameDraft = viewModel.appSettings.yourName
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
        .padding(.horizontal, 6)
        .padding(.vertical, 9)
        .background(Color.clear)
    }

    private func tabButton(_ tab: SettingsTab, icon: String, label: String) -> some View {
        SettingsTabButton(
            tab: tab,
            icon: icon,
            label: label,
            isActive: viewModel.selectedTab == tab,
            accent: accent,
            textSecondary: textSecondary,
            hoverFill: theme.hoverFill.swiftUIColor,
            action: { viewModel.selectedTab = tab }
        )
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
                Toggle(isOn: Binding(
                    get: { viewModel.frontmatterBridge.noteTranscribe ?? viewModel.appSettings.transcribeByDefault },
                    set: { viewModel.setTranscribeThisMeeting($0) }
                )) {
                    HStack(alignment: .center, spacing: 10) {
                        Image(systemName: "waveform").iconStyle(color: textTertiary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Transcribe this meeting").font(.system(size: 13)).foregroundColor(textPrimary)
                        }
                        Spacer()
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                .tint(accent)
            }

            settingsRow {
                Image(systemName: "globe")
                    .iconStyle(color: textTertiary)
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
                Toggle(isOn: Binding(
                    get: { viewModel.frontmatterBridge.noteInPerson ?? viewModel.appSettings.inPersonByDefault },
                    set: { viewModel.setInPersonThisMeeting($0) }
                )) {
                    HStack(alignment: .center, spacing: 10) {
                        Image(systemName: "person.fill").iconStyle(color: textTertiary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("In-person meeting").font(.system(size: 13)).foregroundColor(textPrimary)
                            Text(viewModel.frontmatterBridge.isRecording
                                 ? "Stop recording to change audio sources"
                                 : "Mic only — skips system audio")
                                .font(.system(size: 11)).foregroundColor(textTertiary)
                                .accessibilityIdentifier("inPersonMeetingDetail")
                        }
                        Spacer()
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                .tint(accent)
                .disabled(viewModel.frontmatterBridge.isRecording)
                .accessibilityIdentifier("inPersonMeetingToggle")
            }

            sectionLabel("Calendar")

            settingsRow {
                Image(systemName: "link")
                    .iconStyle(color: textTertiary)
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
                Toggle(isOn: Binding(
                    get: { viewModel.appSettings.transcribeByDefault },
                    set: { viewModel.setTranscribeByDefault($0) }
                )) {
                    HStack(alignment: .center, spacing: 10) {
                        Image(systemName: "waveform").iconStyle(color: textTertiary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Transcribe meetings").font(.system(size: 13)).foregroundColor(textPrimary)
                            Text("Every new meeting starts transcribing")
                                .font(.system(size: 11)).foregroundColor(textTertiary)
                        }
                        Spacer()
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                .tint(accent)
            }

            VStack(alignment: .leading, spacing: 7) {
                settingsRow {
                    Image(systemName: "globe")
                        .iconStyle(color: textTertiary)
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
                            .foregroundColor(accent.opacity(0.82))
                        Text(EffectiveMeetingSettings.languageWarningText)
                            .font(.system(size: 11))
                            .foregroundColor(accent.opacity(0.82))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.leading, 25)
                    .padding(.bottom, 4)
                }
            }
            .padding(.bottom, 2)

            settingsRow {
                Toggle(isOn: Binding(
                    get: { viewModel.appSettings.inPersonByDefault },
                    set: { viewModel.setInPersonByDefault($0) }
                )) {
                    HStack(alignment: .center, spacing: 10) {
                        Image(systemName: "person.fill").iconStyle(color: textTertiary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("In-person meeting").font(.system(size: 13)).foregroundColor(textPrimary)
                            Text("Mic only — skips system audio")
                                .font(.system(size: 11)).foregroundColor(textTertiary)
                        }
                        Spacer()
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                .tint(accent)
            }

            sectionLabel("Models")

            settingsRow {
                Image(systemName: "waveform")
                    .iconStyle(color: textTertiary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Transcription model").font(.system(size: 13)).foregroundColor(textPrimary)
                    Text("On-device · FluidAudio")
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
                .frame(maxWidth: 160)
            }

            settingsRow {
                Image(systemName: "sparkles")
                    .iconStyle(color: textTertiary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Summary model").font(.system(size: 13)).foregroundColor(textPrimary)
                    Text("Used for Generate summary")
                        .font(.system(size: 11)).foregroundColor(textTertiary)
                }
                Spacer()
                Picker("", selection: Binding(
                    get: { summarization.settings.selectedModelSlug },
                    set: { summarization.settings.selectedModelSlug = $0; summarization.saveSettings() }
                )) {
                    ForEach(SummarizationSettings.presets, id: \.slug) { preset in
                        Text(preset.displayName).tag(preset.slug)
                    }
                }
                .pickerStyle(.menu)
                .font(.system(size: 12))
                .frame(maxWidth: 160)
            }

            openRouterSection

            sectionLabel("App")

            settingsRow {
                Image(systemName: "keyboard")
                    .iconStyle(color: textTertiary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Show note hotkey").font(.system(size: 13)).foregroundColor(textPrimary)
                    Text("Toggle the floating note panel")
                        .font(.system(size: 11)).foregroundColor(textTertiary)
                }
                Spacer()
                HotkeyRecorderView(
                    combo: viewModel.appSettings.hotkey,
                    onComboChange: { viewModel.setHotkey($0) }
                )
                .frame(width: 110, height: 26)
                .accessibilityIdentifier("showNoteHotkeyRecorder")
            }

            settingsRow {
                Image(systemName: "record.circle")
                    .iconStyle(color: textTertiary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Start recording hotkey").font(.system(size: 13)).foregroundColor(textPrimary)
                    Text("Begin capture without opening the panel")
                        .font(.system(size: 11)).foregroundColor(textTertiary)
                }
                Spacer()
                HotkeyRecorderView(
                    combo: viewModel.appSettings.recordingHotkey,
                    onComboChange: { viewModel.setRecordingHotkey($0) }
                )
                .frame(width: 110, height: 26)
                .accessibilityIdentifier("startRecordingHotkeyRecorder")
            }

            ForEach(hotkeyWarnings, id: \.self) { warning in
                hotkeyWarningRow(warning)
            }

            settingsRow {
                Toggle(isOn: Binding(
                    get: { viewModel.appSettings.launchAtLogin },
                    set: { viewModel.setLaunchAtLogin($0) }
                )) {
                    HStack(alignment: .center, spacing: 10) {
                        Image(systemName: "power").iconStyle(color: textTertiary)
                        Text("Launch at login").font(.system(size: 13)).foregroundColor(textPrimary)
                        Spacer()
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                .tint(accent)
            }

            settingsRow {
                Image(systemName: "circle.lefthalf.filled")
                    .iconStyle(color: textTertiary)
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
                    .iconStyle(color: textTertiary)
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
                        .stroke(theme.fieldBorder.swiftUIColor, lineWidth: 0.5))
            }

            updatesSettingsSection
        }
    }

    // MARK: - OpenRouter API key

    private var openRouterSection: some View {
        Group {
            sectionLabel("OpenRouter")

            settingsRow {
                Image(systemName: "key")
                    .iconStyle(color: textTertiary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("API key").font(.system(size: 13)).foregroundColor(textPrimary)
                    Text("Required for summaries · stored in Keychain")
                        .font(.system(size: 11)).foregroundColor(textTertiary)
                }
                Spacer()
                if summarization.apiKeyStatusChecked, summarization.apiKeyConfigured {
                    Label("Set", systemImage: "checkmark.seal.fill")
                        .labelStyle(.titleAndIcon)
                        .font(.system(size: 11))
                        .foregroundColor(accent)
                } else if summarization.apiKeyStatusChecked {
                    Text("Not set")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(textTertiary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(controlBg)
                        .clipShape(Capsule())
                } else {
                    Button("Check") { summarization.refreshAPIKeyStatus() }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(accent)
                }
            }

            HStack(spacing: 8) {
                SecureField(
                    summarization.apiKeyStatusChecked && summarization.apiKeyConfigured
                        ? "Enter new key to replace"
                        : "sk-or-\u{2026}",
                    text: $summarization.apiKeyDraft
                )
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(textPrimary)
                .onSubmit { summarization.saveAPIKey() }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(controlBg)
                .cornerRadius(6.5)
                .overlay(RoundedRectangle(cornerRadius: 6.5)
                    .stroke(theme.fieldBorder.swiftUIColor, lineWidth: 0.5))

                Button("Save") { summarization.saveAPIKey() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(summarization.apiKeyDraft.trimmingCharacters(in: .whitespaces).isEmpty ? textTertiary : accent)
                    .disabled(summarization.apiKeyDraft.trimmingCharacters(in: .whitespaces).isEmpty)

                if summarization.apiKeyStatusChecked, summarization.apiKeyConfigured {
                    Button("Clear") { summarization.clearAPIKey() }
                        .buttonStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundColor(textTertiary)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 2)
        }
    }

    // MARK: - Recording content

    private var recordingContent: some View {
        Group {
            sectionLabel("Audio sources")

            settingsRow {
                Toggle(isOn: Binding(
                    get: { viewModel.appSettings.micEnabled },
                    set: { viewModel.setMicEnabled($0) }
                )) {
                    HStack(alignment: .center, spacing: 10) {
                        Image(systemName: "mic").iconStyle(color: textTertiary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Microphone").font(.system(size: 13)).foregroundColor(textPrimary)
                            Text("Your voice — assigned to you")
                                .font(.system(size: 11)).foregroundColor(textTertiary)
                        }
                        Spacer()
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                .tint(accent)
            }

            settingsRow {
                Toggle(isOn: Binding(
                    get: { viewModel.appSettings.systemAudioEnabled },
                    set: { viewModel.setSystemAudioEnabled($0) }
                )) {
                    HStack(alignment: .center, spacing: 10) {
                        Image(systemName: "speaker.wave.2").iconStyle(color: textTertiary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("System audio").font(.system(size: 13)).foregroundColor(textPrimary)
                            Text("Other participants · off for in-person")
                                .font(.system(size: 11)).foregroundColor(textTertiary)
                        }
                        Spacer()
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                .tint(accent)
            }

            sectionLabel("Speaker naming")

            settingsRow {
                Image(systemName: "person")
                    .iconStyle(color: textTertiary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your name").font(.system(size: 13)).foregroundColor(textPrimary)
                    Text("Used for the microphone speaker")
                        .font(.system(size: 11)).foregroundColor(textTertiary)
                }
                Spacer()
                TextField("Name\u{2026}", text: $yourNameDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundColor(textPrimary)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 130)
                    .onChange(of: yourNameDraft) { name in
                        viewModel.setYourName(name)
                    }
            }

            settingsRow {
                Toggle(isOn: Binding(
                    get: { viewModel.appSettings.inferNamesFromCalendar },
                    set: { viewModel.setInferNamesFromCalendar($0) }
                )) {
                    HStack(alignment: .center, spacing: 10) {
                        Image(systemName: "calendar.badge.checkmark").iconStyle(color: textTertiary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Infer names from calendar").font(.system(size: 13)).foregroundColor(textPrimary)
                            Text("Auto-name the other speaker when 1:1")
                                .font(.system(size: 11)).foregroundColor(textTertiary)
                        }
                        Spacer()
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                .tint(accent)
            }
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
                        .foregroundColor(entry.isEnabled ? accent : textTertiary)
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

    // MARK: - Updates content

    @State private var updateCheckStatus: String = "Check for the latest release"
    @State private var isCheckingForUpdates: Bool = false

    private var updatesSettingsSection: some View {
        Group {
            sectionLabel("Software update")

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 22, weight: .light))
                        .foregroundColor(accent)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text("NoteTakr \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(textPrimary)
                        }
                        Text(updateCheckStatus)
                            .font(.system(size: 11))
                            .foregroundColor(textTertiary)
                    }
                    Spacer()
                    Button {
                        checkForUpdates()
                    } label: {
                        HStack(spacing: 5) {
                            if isCheckingForUpdates {
                                ProgressView()
                                    .controlSize(.mini)
                                    .tint(textSecondary)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            Text(isCheckingForUpdates ? "Checking\u{2026}" : "Check Now")
                                .font(.system(size: 12))
                        }
                        .foregroundColor(isCheckingForUpdates ? textTertiary : textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(controlBg)
                        .cornerRadius(7)
                        .overlay(RoundedRectangle(cornerRadius: 7)
                            .stroke(theme.fieldBorder.swiftUIColor, lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                    .disabled(isCheckingForUpdates)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 2)
                .overlay(alignment: .bottom) { Rectangle().fill(hairline).frame(height: 1) }

                settingsRow {
                    Toggle(isOn: Binding(
                        get: { viewModel.appSettings.autoCheckForUpdates },
                        set: { viewModel.setAutoCheckForUpdates($0) }
                    )) {
                        HStack(alignment: .center, spacing: 10) {
                            Image(systemName: "clock.arrow.circlepath").iconStyle(color: textTertiary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Automatically check for updates").font(.system(size: 13)).foregroundColor(textPrimary)
                                Text("Via Sparkle").font(.system(size: 11)).foregroundColor(textTertiary)
                            }
                            Spacer()
                        }
                    }
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .tint(accent)
                }

                settingsRow {
                    Toggle(isOn: Binding(
                        get: { viewModel.appSettings.autoDownloadUpdates },
                        set: { viewModel.setAutoDownloadUpdates($0) }
                    )) {
                        HStack(alignment: .center, spacing: 10) {
                            Image(systemName: "arrow.down.circle").iconStyle(color: textTertiary)
                            Text("Automatically download updates").font(.system(size: 13)).foregroundColor(textPrimary)
                            Spacer()
                        }
                    }
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .tint(accent)
                }
            }

            sectionLabel("Channel")

            settingsRow {
                Image(systemName: "clock")
                    .iconStyle(color: textTertiary)
                Text("Release channel").font(.system(size: 13)).foregroundColor(textPrimary)
                Spacer()
                Text("Stable")
                    .font(.system(size: 12))
                    .foregroundColor(textSecondary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10))
                    .foregroundColor(textTertiary)
            }
        }
    }

    private func checkForUpdates() {
        isCheckingForUpdates = true
        updateCheckStatus = "Checking\u{2026}"
        // Sparkle check is macOS-only; on Linux / simulator this is a no-op UI stub.
        triggerSparkleCheck()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            isCheckingForUpdates = false
            updateCheckStatus = "Last checked just now"
        }
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

            permRow(
                label: "Contacts",
                detail: "Names attendees from email",
                status: permissions.contactsStatus,
                action: { Task { await permissions.requestContactsAccess() } }
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
        PermissionRowButton(
            label: label,
            detail: detail,
            status: status,
            actionTitle: "Grant",
            hairline: hairline,
            hoverFill: theme.hoverFill.swiftUIColor,
            textPrimary: textPrimary,
            textTertiary: textTertiary,
            action: action
        )
        .accessibilityIdentifier("permissionRow_\(label)")
    }

    private var systemAudioRow: some View {
        PermissionRowButton(
            label: "System Audio",
            detail: permissions.systemAudioRestartRequired ? "Restart required for Screen Recording" : "Other participants in calls",
            status: permissions.systemAudioStatus,
            actionTitle: permissions.systemAudioRestartRequired ? "Restart" : "Grant",
            hairline: hairline,
            hoverFill: theme.hoverFill.swiftUIColor,
            textPrimary: textPrimary,
            textTertiary: permissions.systemAudioRestartRequired ? .orange : textTertiary,
            action: {
                if permissions.systemAudioRestartRequired {
                    permissions.restartApp()
                } else {
                    permissions.requestSystemAudioAccess()
                }
            }
        )
        .accessibilityIdentifier("permissionRow_System Audio")
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
                                .stroke(theme.fieldBorder.swiftUIColor, lineWidth: 0.5))
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
    private func settingsRow<Content: View>(@ViewBuilder content: @escaping () -> Content) -> some View {
        SettingsRowView(hairline: hairline, hoverFill: theme.hoverFill.swiftUIColor) {
            content()
        }
    }

    private var hotkeyWarnings: [String] {
        [viewModel.hotkeyConflictMessage].compactMap { $0 } + viewModel.hotkeyRegistrationMessages
    }

    private func hotkeyWarningRow(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundColor(accent.opacity(0.82))
            Text(message)
                .font(.system(size: 11))
                .foregroundColor(accent.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, 25)
        .padding(.bottom, 4)
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

    private func persistModelSettings() {
        try? transcriptionSettingsStore.save(modelSettings)
    }

    private func triggerSparkleCheck() {
        NotificationCenter.default.post(name: .noteTakrCheckForUpdates, object: nil)
    }
}

// MARK: - Tab button with full hit target

private struct SettingsTabButton: View {
    let tab: SettingsTab
    let icon: String
    let label: String
    let isActive: Bool
    let accent: Color
    let textSecondary: Color
    let hoverFill: Color
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
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
            .background(backgroundFill)
            .cornerRadius(9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .contentShape(Rectangle())
        .accessibilityIdentifier("settingsTab_\(tab.accessibilityID)")
    }

    private var backgroundFill: Color {
        if isActive { return accent.opacity(0.12) }
        if isHovering { return hoverFill }
        return .clear
    }
}

private extension SettingsTab {
    var accessibilityID: String {
        switch self {
        case .thisMeeting: return "thisMeeting"
        case .general: return "general"
        case .recording: return "recording"
        case .vocabulary: return "vocabulary"
        case .permissions: return "permissions"
        }
    }
}

// MARK: - Permission row with full hit target

private struct PermissionRowButton: View {
    let label: String
    let detail: String
    let status: PermissionStatus
    let actionTitle: String
    let hairline: Color
    let hoverFill: Color
    let textPrimary: Color
    let textTertiary: Color
    let action: () -> Void

    @State private var isHovering = false

    private var isActionable: Bool { status != .granted }

    var body: some View {
        Group {
            if isActionable {
                Button(action: action) {
                    rowContent
                }
                .buttonStyle(.plain)
            } else {
                rowContent
            }
        }
        .onHover { isHovering = $0 }
        .contentShape(Rectangle())
        .background {
            RoundedRectangle(cornerRadius: 7)
                .fill(isHovering ? hoverFill : Color.clear)
        }
        .overlay(alignment: .bottom) { Rectangle().fill(hairline).frame(height: 1) }
    }

    private var rowContent: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .shadow(color: statusColor.opacity(0.6), radius: 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.system(size: 13)).foregroundColor(textPrimary)
                Text(detail).font(.system(size: 11)).foregroundColor(textTertiary)
            }
            Spacer()
            Text(statusText)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(statusColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 2.5)
                .background(statusColor.opacity(0.13))
                .clipShape(Capsule())
            if isActionable {
                Text(actionTitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(textTertiary)
                    .padding(.leading, 2)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 42)
        .padding(.horizontal, 2)
        .contentShape(Rectangle())
    }

    private var statusText: String {
        switch status {
        case .granted: return "Granted"
        case .denied: return "Denied"
        case .notDetermined: return "Needs Access"
        }
    }

    private var statusColor: Color {
        switch status {
        case .granted: return .green
        case .denied: return .orange
        case .notDetermined: return .orange
        }
    }
}

// MARK: - Settings row container with hover state

/// Wraps any settings row content with full-width hover highlighting.
/// Hover state is tracked independently of selection/active state so that
/// hovering a row's text never incorrectly shows the row as "selected".
private struct SettingsRowView<Content: View>: View {
    let hairline: Color
    let hoverFill: Color
    @ViewBuilder let content: () -> Content

    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            content()
        }
        .frame(maxWidth: .infinity, minHeight: 42)
        .contentShape(Rectangle())
        .background {
            RoundedRectangle(cornerRadius: 7)
                .fill(isHovering ? hoverFill : Color.clear)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(hairline).frame(height: 1)
        }
        .onHover { isHovering = $0 }
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
    func iconStyle(color: Color) -> some View {
        self.font(.system(size: 14, weight: .light))
            .frame(width: 15, height: 15)
            .foregroundColor(color)
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
