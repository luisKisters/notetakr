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
    private var _hotkey: String = "⌃⌥⌘N"
    private var _launchAtLogin: Bool = false
    private var _notesFolderPath: String? = nil

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

    public var hotkey: String {
        get { _hotkey }
        set { _hotkey = newValue; saveToDisk() }
    }

    public var launchAtLogin: Bool {
        get { _launchAtLogin }
        set { _launchAtLogin = newValue; saveToDisk() }
    }

    public var notesFolderPath: String? {
        get { _notesFolderPath }
        set { _notesFolderPath = newValue; saveToDisk() }
    }

    // MARK: - Persistence

    private struct Payload: Codable {
        var transcribeByDefault: Bool?
        var defaultLanguage: String?
        var inPersonByDefault: Bool?
        var appearance: Appearance?
        var hotkey: String?
        var launchAtLogin: Bool?
        var notesFolderPath: String?
    }

    private func loadFromDisk() {
        guard let data = try? Data(contentsOf: fileURL),
              let payload = try? JSONDecoder().decode(Payload.self, from: data)
        else { return }
        if let v = payload.transcribeByDefault { _transcribeByDefault = v }
        if let v = payload.defaultLanguage     { _defaultLanguage = v }
        if let v = payload.inPersonByDefault   { _inPersonByDefault = v }
        if let v = payload.appearance          { _appearance = v }
        if let v = payload.hotkey              { _hotkey = v }
        if let v = payload.launchAtLogin       { _launchAtLogin = v }
        _notesFolderPath = payload.notesFolderPath  // nil is valid
    }

    private func saveToDisk() {
        let payload = Payload(
            transcribeByDefault: _transcribeByDefault,
            defaultLanguage: _defaultLanguage,
            inPersonByDefault: _inPersonByDefault,
            appearance: _appearance,
            hotkey: _hotkey,
            launchAtLogin: _launchAtLogin,
            notesFolderPath: _notesFolderPath
        )
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

// MARK: - NoteDefaultsProviding conformance

extension AppSettingsStore: NoteDefaultsProviding {}
