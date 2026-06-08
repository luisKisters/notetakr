import AppKit
import SwiftUI
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

struct SettingsView: View {
    @StateObject private var permissions = AudioPermissionManager()
    @StateObject private var vocab = VocabularyViewModel()
    @State private var newPhrase: String = ""

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
        }
        .formStyle(.grouped)
        .frame(minWidth: 420, minHeight: 340)
        .onAppear {
            permissions.refresh()
            vocab.reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissions.refresh()
        }
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

    private func submitNewPhrase() {
        guard !newPhrase.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        vocab.add(phrase: newPhrase)
        newPhrase = ""
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
                    }
                    Button("Open Settings") {
                        permissions.requestSystemAudioAccess()
                    }
                    .controlSize(.small)
                    .accessibilityIdentifier("grantAccess_System Audio")
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
