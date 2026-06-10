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
    @Published var selectedTab: SettingsTab = .thisMeeting
    @Published var isVisible: Bool = false
    @Published var currentAppearance: Appearance

    let frontmatterBridge: FrontmatterPresenterBridge
    let appSettings: AppSettingsStore

    /// Called when the user records a new hotkey so the coordinator can re-register.
    var onHotkeyChange: ((HotkeyCombo) -> Void)?

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

    func setHotkey(_ combo: HotkeyCombo) {
        appSettings.hotkey = combo
        onHotkeyChange?(combo)
    }

    // MARK: - Sheet lifecycle

    func close() {
        isVisible = false
    }
}
