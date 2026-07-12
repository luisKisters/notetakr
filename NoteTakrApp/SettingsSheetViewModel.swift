import Foundation
import NoteTakrKit

// MARK: - Tab

enum SettingsTab: CaseIterable, Equatable {
    case thisMeeting
    case general
    case recording
    case vocabulary
    case permissions
}

// MARK: - ViewModel

/// Drives the settings bottom sheet. Bridges This-Meeting mutations to
/// FrontmatterPresenterBridge and General mutations to AppSettingsStore.
@MainActor
final class SettingsSheetViewModel: ObservableObject {
    enum HotkeyRegistrationRole: CaseIterable, Hashable {
        case showNote
        case recording
    }

    @Published var selectedTab: SettingsTab = .thisMeeting
    @Published var isVisible: Bool = false
    @Published var currentAppearance: Appearance
    @Published private(set) var hotkeyConflictMessage: String?
    @Published private(set) var hotkeyRegistrationMessages: [String] = []

    let frontmatterBridge: FrontmatterPresenterBridge
    let appSettings: AppSettingsStore
    private var hotkeyRegistrationMessagesByRole: [HotkeyRegistrationRole: String] = [:]

    /// Called when the user records a new hotkey so the coordinator can re-register.
    var onHotkeyChange: ((HotkeyCombo) -> Void)?
    /// Called when the user records a new recording hotkey so the coordinator can re-register.
    var onRecordingHotkeyChange: ((HotkeyCombo) -> Void)?
    /// Called when the user toggles auto-check-for-updates so the live updater can be updated.
    var onAutoCheckForUpdatesChange: ((Bool) -> Void)?
    /// Called when the user toggles auto-download-updates so the live updater can be updated.
    var onAutoDownloadUpdatesChange: ((Bool) -> Void)?

    init(frontmatterBridge: FrontmatterPresenterBridge, appSettings: AppSettingsStore) {
        self.frontmatterBridge = frontmatterBridge
        self.appSettings = appSettings
        self.currentAppearance = appSettings.appearance
    }

    // MARK: - Derived state

    var showScopeBanner: Bool { selectedTab == .thisMeeting }

    /// The language warning surfaces only in General tab when a fixed language is the global default.
    var showLanguageWarning: Bool { appSettings.defaultLanguage != .auto }

    var noteTitle: String { frontmatterBridge.noteTitle }

    // MARK: - This Meeting mutations (write to frontmatter only)

    func setTranscribeThisMeeting(_ value: Bool) {
        frontmatterBridge.setTranscribe(value)
    }

    func setLanguageThisMeeting(_ lang: TranscribeLanguage) {
        frontmatterBridge.setLanguage(lang)
    }

    func setInPersonThisMeeting(_ value: Bool) {
        frontmatterBridge.setInPerson(value)
    }

    func unlinkEvent() {
        frontmatterBridge.unlinkEvent()
    }

    func addVocabularyTermThisMeeting(_ term: String) {
        frontmatterBridge.addVocabularyTerm(term)
    }

    func removeVocabularyTermThisMeeting(_ term: String) {
        frontmatterBridge.removeVocabularyTerm(term)
    }

    // MARK: - General mutations (write to AppSettingsStore only)

    func setTranscribeByDefault(_ value: Bool) {
        appSettings.transcribeByDefault = value
    }

    func setDefaultLanguage(_ lang: TranscribeLanguage) {
        appSettings.defaultLanguage = lang
    }

    func setInPersonByDefault(_ value: Bool) {
        appSettings.inPersonByDefault = value
    }

    func setLaunchAtLogin(_ value: Bool) {
        appSettings.launchAtLogin = value
    }

    func setAppearance(_ appearance: Appearance) {
        appSettings.appearance = appearance
        currentAppearance = appearance
    }

    @discardableResult
    func setHotkey(_ combo: HotkeyCombo) -> Bool {
        guard combo != appSettings.recordingHotkey else {
            hotkeyConflictMessage = Self.hotkeyConflictText
            return false
        }
        appSettings.hotkey = combo
        hotkeyConflictMessage = nil
        onHotkeyChange?(combo)
        return true
    }

    @discardableResult
    func setRecordingHotkey(_ combo: HotkeyCombo) -> Bool {
        guard combo != appSettings.hotkey else {
            hotkeyConflictMessage = Self.hotkeyConflictText
            return false
        }
        appSettings.recordingHotkey = combo
        hotkeyConflictMessage = nil
        onRecordingHotkeyChange?(combo)
        return true
    }

    func setHotkeyRegistrationMessage(_ message: String?, for role: HotkeyRegistrationRole) {
        if let message {
            hotkeyRegistrationMessagesByRole[role] = message
        } else {
            hotkeyRegistrationMessagesByRole.removeValue(forKey: role)
        }
        hotkeyRegistrationMessages = HotkeyRegistrationRole.allCases.compactMap {
            hotkeyRegistrationMessagesByRole[$0]
        }
    }

    func setYourName(_ name: String) {
        appSettings.yourName = name
    }

    func setInferNamesFromCalendar(_ value: Bool) {
        appSettings.inferNamesFromCalendar = value
    }

    func setMicEnabled(_ value: Bool) {
        appSettings.micEnabled = value
    }

    func setSystemAudioEnabled(_ value: Bool) {
        appSettings.systemAudioEnabled = value
    }

    func setAutoCheckForUpdates(_ value: Bool) {
        appSettings.autoCheckForUpdates = value
        onAutoCheckForUpdatesChange?(value)
    }

    func setAutoDownloadUpdates(_ value: Bool) {
        appSettings.autoDownloadUpdates = value
        onAutoDownloadUpdatesChange?(value)
    }

    // MARK: - Sheet lifecycle

    func close() {
        isVisible = false
    }

    private static let hotkeyConflictText =
        "Choose different shortcuts for showing the note and starting recording."
}
