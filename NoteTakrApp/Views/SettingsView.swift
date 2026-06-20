import AppKit
import SwiftUI
import NoteTakrKit
import NoteTakrCore

@MainActor
final class VocabularyViewModel: ObservableObject {
    @Published var entries: [VocabularyEntry] = []
    private let store: VocabularyStore

    init() {
        let fileURL = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("NoteTakr/vocabulary.json")
        store = VocabularyStore(fileURL: fileURL)
        reload()
    }

    func reload() {
        entries = (try? store.load()) ?? []
    }

    func add(phrase: String) {
        let trimmed = phrase.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        guard !entries.contains(where: { $0.phrase.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }
        entries.append(VocabularyEntry(phrase: trimmed))
        persist()
    }

    func remove(at offsets: IndexSet) {
        entries.remove(atOffsets: offsets)
        persist()
    }

    func toggle(_ entry: VocabularyEntry) {
        guard let idx = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[idx].isEnabled.toggle()
        persist()
    }

    func persist() {
        try? store.save(entries)
    }
}

@MainActor
final class SummarizationViewModel: ObservableObject {
    @Published var settings: SummarizationSettings
    @Published var templates: [SummaryTemplate]
    @Published var apiKeyConfigured: Bool
    @Published var apiKeyStatusChecked: Bool
    @Published var apiKeyDraft: String = ""

    private let settingsStore: SummarizationSettingsStore
    private let templateStore: SummaryTemplateStore
    private let keychain = KeychainStore()

    init() {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
        settingsStore = SummarizationSettingsStore(
            fileURL: base.appendingPathComponent("NoteTakr/summarization-settings.json")
        )
        templateStore = SummaryTemplateStore(
            fileURL: base.appendingPathComponent("NoteTakr/summary-templates.json")
        )
        settings = settingsStore.load()
        templates = templateStore.load()
        // Do NOT read the keychain here. `SecItemCopyMatching` triggers a macOS keychain
        // access prompt, and reading at init/reload would fire it unprompted. Defer the
        // check to an explicit user action (opening the section, saving, or generating).
        apiKeyConfigured = false
        apiKeyStatusChecked = false
        normalizeActiveTemplate()
    }

    func reload() {
        settings = settingsStore.load()
        templates = templateStore.load()
        // Intentionally NOT re-reading the keychain here (see init). Use refreshAPIKeyStatus()
        // from an explicit user action instead.
        apiKeyStatusChecked = false
        normalizeActiveTemplate()
    }

    /// Reads the keychain to update `apiKeyConfigured`. Call only from an explicit user
    /// action (e.g. the Check button), never at init, reload, or app launch.
    func refreshAPIKeyStatus() {
        apiKeyConfigured = keychain.hasValue
        apiKeyStatusChecked = true
    }

    private func normalizeActiveTemplate() {
        if settings.activeTemplateID == nil
            || !templates.contains(where: { $0.id == settings.activeTemplateID }) {
            settings.activeTemplateID = templates.first?.id
            saveSettings()
        }
    }

    func saveSettings() { try? settingsStore.save(settings) }
    func saveTemplates() { try? templateStore.save(templates) }

    // API key (Keychain)

    func saveAPIKey() {
        let trimmed = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try? keychain.save(trimmed)
        apiKeyConfigured = true
        apiKeyStatusChecked = true
        apiKeyDraft = ""
    }

    func clearAPIKey() {
        keychain.delete()
        apiKeyConfigured = false
        apiKeyStatusChecked = true
        apiKeyDraft = ""
    }

    // Templates

    func template(id: UUID?) -> SummaryTemplate? {
        guard let id else { return nil }
        return templates.first { $0.id == id }
    }

    func update(_ template: SummaryTemplate) {
        guard let idx = templates.firstIndex(where: { $0.id == template.id }) else { return }
        templates[idx] = template
        saveTemplates()
    }

    func addTemplate() {
        let new = SummaryTemplate(name: "New Template", prompt: "", isBuiltIn: false)
        templates.append(new)
        settings.activeTemplateID = new.id
        saveTemplates()
        saveSettings()
    }

    func deleteActiveTemplate() {
        guard let id = settings.activeTemplateID,
              let idx = templates.firstIndex(where: { $0.id == id }),
              templates.count > 1
        else { return }
        templates.remove(at: idx)
        settings.activeTemplateID = templates.first?.id
        saveTemplates()
        saveSettings()
    }

    func resetBuiltInTemplates() {
        var custom = templates.filter { !$0.isBuiltIn }
        custom.insert(contentsOf: SummaryTemplate.defaults, at: 0)
        templates = custom
        normalizeActiveTemplate()
        saveTemplates()
    }
}

struct SettingsView: View {
    @StateObject private var permissions = AudioPermissionManager()
    @StateObject private var vocab = VocabularyViewModel()
    @StateObject private var summarization = SummarizationViewModel()
    @State private var newPhrase: String = ""
    @State private var modelSettings: TranscriptionModelSettings = .default
    private let transcriptionSettingsStore = TranscriptionSettingsStore()

    var body: some View {
        Form {
            Section("Permissions") {
                permissionRow(
                    label: "Microphone",
                    detail: "Required for recording your voice",
                    status: permissions.microphoneStatus,
                    action: {
                        Task { await permissions.requestMicrophoneAccess() }
                    }
                )
                permissionRow(
                    label: "Calendar",
                    detail: "Required to detect upcoming meetings",
                    status: permissions.calendarStatus,
                    action: {
                        Task { await permissions.requestCalendarAccess() }
                    }
                )
                systemAudioPermissionRow()
            }

            Section {
                Button("Refresh Status") {
                    permissions.refresh(includeCalendar: true)
                }
                .accessibilityIdentifier("refreshPermissionsButton")
            }

            Section {
                Text(systemAudioHelpText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("systemAudioNote")
            }

            Section("Transcription Model") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Status")
                            .fontWeight(.medium)
                        Text(modelStatusText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .accessibilityIdentifier("transcriptionModelStatus")
                    }
                    Spacer()
                    transcriptionModelStatusBadge
                }
                .padding(.vertical, 2)

                Picker("Model Version", selection: modelVersionBinding) {
                    ForEach(FluidAudioModelVersion.allCases, id: \.self) { version in
                        Text(version.displayName).tag(version)
                    }
                }
                .accessibilityIdentifier("transcriptionModelVersionPicker")

                HStack {
                    Button("Select Model Folder...") {
                        selectModelFolder()
                    }
                    .accessibilityIdentifier("selectModelFolderButton")

                    Button("Use Automatic Download") {
                        updateModelSettings(source: .fluidAudioDefaultCache)
                    }
                    .accessibilityIdentifier("useAutomaticModelDownloadButton")

                    Button("Clear") {
                        updateModelSettings(source: .notConfigured)
                    }
                    .accessibilityIdentifier("clearModelSettingsButton")
                    .disabled(modelSettings.source == .notConfigured)
                }
            }

            Section("Vocabulary Boosting") {
                if vocab.entries.isEmpty {
                    Text("No custom vocabulary entries. Add phrases to improve transcription accuracy.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("vocabEmptyPlaceholder")
                } else {
                    ForEach(vocab.entries) { entry in
                        vocabRow(entry)
                    }
                    .onDelete { vocab.remove(at: $0) }
                }
                HStack {
                    TextField("Add phrase…", text: $newPhrase)
                        .accessibilityIdentifier("newPhraseField")
                        .onSubmit { submitNewPhrase() }
                    Button("Add") { submitNewPhrase() }
                        .disabled(newPhrase.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityIdentifier("addPhraseButton")
                }
            }

            summarizationSection
        }
        .formStyle(.grouped)
        .frame(minWidth: 420, minHeight: 340)
        .onAppear {
            permissions.refresh()
            vocab.reload()
            summarization.reload()
            modelSettings = transcriptionSettingsStore.load()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissions.refresh()
            modelSettings = transcriptionSettingsStore.load()
        }
    }

    private var modelVersionBinding: Binding<FluidAudioModelVersion> {
        Binding(
            get: { modelSettings.modelVersion },
            set: { newValue in
                modelSettings.modelVersion = newValue
                persistModelSettings()
            }
        )
    }

    private var modelStatusText: String {
        switch modelSettings.source {
        case .notConfigured:
            return "Not configured"
        case .localFolder(let url):
            return "Using selected folder: \(url.path)"
        case .fluidAudioDefaultCache:
            return "Using FluidAudio cache"
        }
    }

    @ViewBuilder
    private var transcriptionModelStatusBadge: some View {
        let (label, color): (String, Color) = switch modelSettings.source {
        case .notConfigured:
            ("Not Set", .orange)
        case .localFolder:
            ("Folder", .green)
        case .fluidAudioDefaultCache:
            ("Auto", .green)
        }
        Text(label)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
            .accessibilityIdentifier("transcriptionModelStatusBadge")
    }

    private var systemAudioPermissionDetail: String {
        if permissions.systemAudioStatus == .granted {
            return "Screen Recording granted — system audio capture ready"
        }
        if permissions.systemAudioRestartRequired {
            return "Restart required to activate Screen Recording"
        }
        return "Requires Screen Recording permission (ScreenCaptureKit)"
    }

    private var systemAudioHelpText: String {
        "System audio capture requires Screen Recording permission in System Settings › Privacy & Security."
    }

    @ViewBuilder
    private var systemAudioStatusBadge: some View {
        if permissions.systemAudioRestartRequired {
            Text("Restart Required")
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.orange.opacity(0.15))
                .foregroundStyle(Color.orange)
                .clipShape(Capsule())
                .accessibilityIdentifier("permissionStatus_restartRequired")
        } else {
            statusBadge(permissions.systemAudioStatus)
        }
    }

    @ViewBuilder
    private func vocabRow(_ entry: VocabularyEntry) -> some View {
        HStack(spacing: 10) {
            Image(systemName: entry.isEnabled ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(entry.isEnabled ? Color.green : Color.secondary)
                .onTapGesture { vocab.toggle(entry) }
                .accessibilityIdentifier("vocabToggle_\(entry.phrase)")
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.phrase)
                    .fontWeight(.medium)
                if !entry.aliases.isEmpty {
                    Text("Also: \(entry.aliases.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text("×\(String(format: "%.1f", entry.boostingWeight))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("vocabEntry_\(entry.phrase)")
    }

    // MARK: - Summarization

    @ViewBuilder
    private var summarizationSection: some View {
        Section("Summarization") {
            // API key
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("OpenRouter API Key")
                        .fontWeight(.medium)
                    Spacer()
                    if summarization.apiKeyStatusChecked, summarization.apiKeyConfigured {
                        Label("Configured", systemImage: "checkmark.seal.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                            .accessibilityIdentifier("openRouterKeyConfigured")
                    } else if summarization.apiKeyStatusChecked {
                        Text("Not configured")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("openRouterKeyNotConfigured")
                    } else {
                        Button("Check") { summarization.refreshAPIKeyStatus() }
                            .controlSize(.small)
                            .accessibilityIdentifier("checkOpenRouterKeyButton")
                    }
                }
                HStack {
                    SecureField(
                        summarization.apiKeyStatusChecked && summarization.apiKeyConfigured
                            ? "Enter a new key to replace"
                            : "sk-or-…",
                        text: $summarization.apiKeyDraft
                    )
                    .accessibilityIdentifier("openRouterKeyField")
                    .onSubmit { summarization.saveAPIKey() }
                    Button("Save") { summarization.saveAPIKey() }
                        .disabled(summarization.apiKeyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityIdentifier("saveOpenRouterKeyButton")
                    if summarization.apiKeyStatusChecked, summarization.apiKeyConfigured {
                        Button("Clear") { summarization.clearAPIKey() }
                            .accessibilityIdentifier("clearOpenRouterKeyButton")
                    }
                }
                Text("Stored securely in the macOS Keychain. Required for summaries.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)

            // Model
            Picker("Model", selection: modelPresetBinding) {
                ForEach(SummarizationSettings.presets) { preset in
                    Text(preset.displayName).tag(preset.slug)
                }
                if !SummarizationSettings.presets.contains(where: { $0.slug == summarization.settings.selectedModelSlug }) {
                    Text("Custom").tag(summarization.settings.selectedModelSlug)
                }
            }
            .accessibilityIdentifier("summarizationModelPicker")

            HStack {
                Text("Model slug")
                    .foregroundStyle(.secondary)
                TextField("provider/model", text: modelSlugBinding)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("summarizationModelSlugField")
            }

            Toggle("Summarize automatically after transcription", isOn: autoSummarizeBinding)
                .accessibilityIdentifier("autoSummarizeToggle")

            // Templates
            Picker("Active Template", selection: activeTemplateBinding) {
                ForEach(summarization.templates) { template in
                    Text(template.name).tag(Optional(template.id))
                }
            }
            .accessibilityIdentifier("activeTemplatePicker")

            if let id = summarization.settings.activeTemplateID {
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Template name", text: templateNameBinding(id))
                        .accessibilityIdentifier("templateNameField")
                    Text("Prompt (system instruction)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: templatePromptBinding(id))
                        .frame(minHeight: 100)
                        .font(.callout)
                        .accessibilityIdentifier("templatePromptEditor")
                }
                .padding(.vertical, 2)
            }

            HStack {
                Button("Add Template") { summarization.addTemplate() }
                    .accessibilityIdentifier("addTemplateButton")
                Button("Delete") { summarization.deleteActiveTemplate() }
                    .disabled(summarization.templates.count <= 1)
                    .accessibilityIdentifier("deleteTemplateButton")
                Spacer()
                Button("Reset Built-ins") { summarization.resetBuiltInTemplates() }
                    .accessibilityIdentifier("resetTemplatesButton")
            }
        }
    }

    private var modelPresetBinding: Binding<String> {
        Binding(
            get: { summarization.settings.selectedModelSlug },
            set: { summarization.settings.selectedModelSlug = $0; summarization.saveSettings() }
        )
    }

    private var modelSlugBinding: Binding<String> {
        Binding(
            get: { summarization.settings.selectedModelSlug },
            set: { summarization.settings.selectedModelSlug = $0; summarization.saveSettings() }
        )
    }

    private var autoSummarizeBinding: Binding<Bool> {
        Binding(
            get: { summarization.settings.autoSummarize },
            set: { summarization.settings.autoSummarize = $0; summarization.saveSettings() }
        )
    }

    private var activeTemplateBinding: Binding<UUID?> {
        Binding(
            get: { summarization.settings.activeTemplateID },
            set: { summarization.settings.activeTemplateID = $0; summarization.saveSettings() }
        )
    }

    private func templateNameBinding(_ id: UUID) -> Binding<String> {
        Binding(
            get: { summarization.template(id: id)?.name ?? "" },
            set: { newValue in
                guard var t = summarization.template(id: id) else { return }
                t.name = newValue
                summarization.update(t)
            }
        )
    }

    private func templatePromptBinding(_ id: UUID) -> Binding<String> {
        Binding(
            get: { summarization.template(id: id)?.prompt ?? "" },
            set: { newValue in
                guard var t = summarization.template(id: id) else { return }
                t.prompt = newValue
                summarization.update(t)
            }
        )
    }

    private func submitNewPhrase() {
        guard !newPhrase.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        vocab.add(phrase: newPhrase)
        newPhrase = ""
    }

    private func selectModelFolder() {
        let panel = NSOpenPanel()
        panel.title = "Select FluidAudio Model Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false

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

    @ViewBuilder
    private func systemAudioPermissionRow() -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("System Audio")
                        .fontWeight(.medium)
                    Text(systemAudioPermissionDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if permissions.systemAudioStatus != .granted {
                    if permissions.systemAudioRestartRequired {
                        Button("Restart App") {
                            permissions.restartApp()
                        }
                        .controlSize(.small)
                        .accessibilityIdentifier("restartForSystemAudio")
                    } else {
                        Button("Open Settings") {
                            permissions.requestSystemAudioAccess()
                        }
                        .controlSize(.small)
                        .accessibilityIdentifier("grantAccess_System Audio")
                    }
                }
                systemAudioStatusBadge
            }
            .padding(.vertical, 2)

            if permissions.systemAudioRestartRequired {
                Label(
                    "macOS applies Screen Recording permission only after the app restarts.",
                    systemImage: "info.circle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
                .accessibilityIdentifier("screenRecordingRestartExplanation")
            }
        }
        .accessibilityIdentifier("permissionRow_System Audio")
    }

    @ViewBuilder
    private func permissionRow(
        label: String,
        detail: String,
        status: PermissionStatus,
        buttonTitle: String = "Grant Access",
        action: @escaping () -> Void
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .fontWeight(.medium)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if status != .granted {
                Button(buttonTitle, action: action)
                    .controlSize(.small)
                    .accessibilityIdentifier("grantAccess_\(label)")
            }
            statusBadge(status)
        }
        .padding(.vertical, 2)
        .accessibilityIdentifier("permissionRow_\(label)")
    }

    @ViewBuilder
    private func statusBadge(_ status: PermissionStatus) -> some View {
        let (label, color): (String, Color) = switch status {
        case .granted: ("Granted", .green)
        case .denied: ("Denied", .red)
        case .notDetermined: ("Not Set", .orange)
        }
        Text(label)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
            .accessibilityIdentifier("permissionStatus_\(status.rawValue)")
    }
}
