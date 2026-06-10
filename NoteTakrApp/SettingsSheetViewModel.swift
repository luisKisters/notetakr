import Foundation
import NoteTakrKit

// MARK: - Tab

public enum SettingsTab: CaseIterable, Equatable {
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
public final class SettingsSheetViewModel: ObservableObject {
    @Published public var selectedTab: SettingsTab = .thisMeeting
    @Published public var isVisible: Bool = false

    public let frontmatterBridge: FrontmatterPresenterBridge
    public let appSettings: AppSettingsStore

    public init(frontmatterBridge: FrontmatterPresenterBridge, appSettings: AppSettingsStore) {
        self.frontmatterBridge = frontmatterBridge
        self.appSettings = appSettings
    }

    // MARK: - Derived state

    public var showScopeBanner: Bool { selectedTab == .thisMeeting }

    /// The language warning surfaces only in General tab when a fixed language is the global default.
    public var showLanguageWarning: Bool { appSettings.defaultLanguage != .auto }

    public var noteTitle: String { frontmatterBridge.noteTitle }

    // MARK: - This Meeting mutations (write to frontmatter only)

    public func setTranscribeThisMeeting(_ value: Bool) {
        frontmatterBridge.setTranscribe(value)
    }

    public func setLanguageThisMeeting(_ lang: TranscribeLanguage) {
        frontmatterBridge.setLanguage(lang)
    }

    public func setInPersonThisMeeting(_ value: Bool) {
        frontmatterBridge.setInPerson(value)
    }

    public func unlinkEvent() {
        frontmatterBridge.unlinkEvent()
    }

    public func addVocabularyTermThisMeeting(_ term: String) {
        frontmatterBridge.addVocabularyTerm(term)
    }

    public func removeVocabularyTermThisMeeting(_ term: String) {
        frontmatterBridge.removeVocabularyTerm(term)
    }

    // MARK: - General mutations (write to AppSettingsStore only)

    public func setTranscribeByDefault(_ value: Bool) {
        appSettings.transcribeByDefault = value
    }

    public func setDefaultLanguage(_ lang: TranscribeLanguage) {
        appSettings.defaultLanguage = lang
    }

    public func setInPersonByDefault(_ value: Bool) {
        appSettings.inPersonByDefault = value
    }

    public func setLaunchAtLogin(_ value: Bool) {
        appSettings.launchAtLogin = value
    }

    // MARK: - Sheet lifecycle

    public func close() {
        isVisible = false
    }
}
