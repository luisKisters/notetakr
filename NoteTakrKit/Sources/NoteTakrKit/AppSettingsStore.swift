import Foundation

// MARK: - Appearance

public enum Appearance: String, Codable, CaseIterable, Equatable {
    case glass
    case dark
    case light
}

// MARK: - AppSettingsStore

public final class AppSettingsStore {
    private let fileURL: URL

    private var _transcribeByDefault: Bool = true
    private var _defaultLanguage: String = "auto"
    private var _inPersonByDefault: Bool = false
    private var _appearance: Appearance = .glass
    // try! is safe: the default string is a known-valid combo
    private var _hotkey: HotkeyCombo = try! HotkeyCombo.parse("⌃⌥⌘N")
    private var _recordingHotkey: HotkeyCombo = try! HotkeyCombo.parse("⌃⌥⌘R")
    private var _launchAtLogin: Bool = false
    private var _notesFolderPath: String? = nil
    private var _yourName: String = ""
    private var _inferNamesFromCalendar: Bool = true
    private var _micEnabled: Bool = true
    private var _systemAudioEnabled: Bool = true
    private var _autoCheckForUpdates: Bool = true
    private var _autoDownloadUpdates: Bool = false
    private var _localOnlyByDefault: Bool = false

    public init(root: URL) {
        fileURL = root.appendingPathComponent("settings.json")
        loadFromDisk()
    }

    // MARK: - Public properties

    public var transcribeByDefault: Bool {
        get { _transcribeByDefault }
        set { _transcribeByDefault = newValue; saveToDisk() }
    }

    public var defaultLanguage: TranscribeLanguage {
        get { TranscribeLanguage(rawValue: _defaultLanguage) }
        set { _defaultLanguage = newValue.rawValue; saveToDisk() }
    }

    public var inPersonByDefault: Bool {
        get { _inPersonByDefault }
        set { _inPersonByDefault = newValue; saveToDisk() }
    }

    public var appearance: Appearance {
        get { _appearance }
        set { _appearance = newValue; saveToDisk() }
    }

    public var hotkey: HotkeyCombo {
        get { _hotkey }
        set { _hotkey = newValue; saveToDisk() }
    }

    public var recordingHotkey: HotkeyCombo {
        get { _recordingHotkey }
        set { _recordingHotkey = newValue; saveToDisk() }
    }

    public var launchAtLogin: Bool {
        get { _launchAtLogin }
        set { _launchAtLogin = newValue; saveToDisk() }
    }

    public var notesFolderPath: String? {
        get { _notesFolderPath }
        set { _notesFolderPath = newValue; saveToDisk() }
    }

    public var yourName: String {
        get { _yourName }
        set { _yourName = newValue; saveToDisk() }
    }

    public var inferNamesFromCalendar: Bool {
        get { _inferNamesFromCalendar }
        set { _inferNamesFromCalendar = newValue; saveToDisk() }
    }

    public var micEnabled: Bool {
        get { _micEnabled }
        set { _micEnabled = newValue; saveToDisk() }
    }

    public var systemAudioEnabled: Bool {
        get { _systemAudioEnabled }
        set { _systemAudioEnabled = newValue; saveToDisk() }
    }

    public var autoCheckForUpdates: Bool {
        get { _autoCheckForUpdates }
        set { _autoCheckForUpdates = newValue; saveToDisk() }
    }

    public var autoDownloadUpdates: Bool {
        get { _autoDownloadUpdates }
        set { _autoDownloadUpdates = newValue; saveToDisk() }
    }

    public var localOnlyByDefault: Bool {
        get { _localOnlyByDefault }
        set { _localOnlyByDefault = newValue; saveToDisk() }
    }

    // MARK: - Persistence

    private struct Payload: Codable {
        var transcribeByDefault: Bool?
        var defaultLanguage: String?
        var inPersonByDefault: Bool?
        var appearance: Appearance?
        var hotkey: HotkeyCombo?
        var recordingHotkey: HotkeyCombo?
        var launchAtLogin: Bool?
        var notesFolderPath: String?
        var yourName: String?
        var inferNamesFromCalendar: Bool?
        var micEnabled: Bool?
        var systemAudioEnabled: Bool?
        var autoCheckForUpdates: Bool?
        var autoDownloadUpdates: Bool?
        var localOnlyByDefault: Bool?
    }

    private func loadFromDisk() {
        guard let data = try? Data(contentsOf: fileURL),
              let payload = try? JSONDecoder().decode(Payload.self, from: data)
        else { return }
        if let v = payload.transcribeByDefault   { _transcribeByDefault = v }
        if let v = payload.defaultLanguage       { _defaultLanguage = v }
        if let v = payload.inPersonByDefault     { _inPersonByDefault = v }
        if let v = payload.appearance            { _appearance = v }
        if let v = payload.hotkey                { _hotkey = v }
        if let v = payload.recordingHotkey       { _recordingHotkey = v }
        if let v = payload.launchAtLogin         { _launchAtLogin = v }
        _notesFolderPath = payload.notesFolderPath
        if let v = payload.yourName              { _yourName = v }
        if let v = payload.inferNamesFromCalendar { _inferNamesFromCalendar = v }
        if let v = payload.micEnabled            { _micEnabled = v }
        if let v = payload.systemAudioEnabled    { _systemAudioEnabled = v }
        if let v = payload.autoCheckForUpdates   { _autoCheckForUpdates = v }
        if let v = payload.autoDownloadUpdates   { _autoDownloadUpdates = v }
        if let v = payload.localOnlyByDefault    { _localOnlyByDefault = v }
    }

    private func saveToDisk() {
        let payload = Payload(
            transcribeByDefault: _transcribeByDefault,
            defaultLanguage: _defaultLanguage,
            inPersonByDefault: _inPersonByDefault,
            appearance: _appearance,
            hotkey: _hotkey,
            recordingHotkey: _recordingHotkey,
            launchAtLogin: _launchAtLogin,
            notesFolderPath: _notesFolderPath,
            yourName: _yourName,
            inferNamesFromCalendar: _inferNamesFromCalendar,
            micEnabled: _micEnabled,
            systemAudioEnabled: _systemAudioEnabled,
            autoCheckForUpdates: _autoCheckForUpdates,
            autoDownloadUpdates: _autoDownloadUpdates,
            localOnlyByDefault: _localOnlyByDefault
        )
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: fileURL, options: .atomic)
    }
}

// MARK: - NoteDefaultsProviding conformance

extension AppSettingsStore: NoteDefaultsProviding {}
