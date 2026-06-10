import Foundation

// MARK: - EffectiveMeetingSettings

public struct EffectiveMeetingSettings: Equatable {
    public var transcribe: Bool
    public var language: TranscribeLanguage
    public var inPerson: Bool
    public var vocabulary: [String]
    public var languageWarning: String?

    public static let languageWarningText =
        "Meetings in any other language will be transcribed incorrectly. Auto-detect is recommended."

    public init(
        transcribe: Bool,
        language: TranscribeLanguage,
        inPerson: Bool,
        vocabulary: [String],
        languageWarning: String? = nil
    ) {
        self.transcribe = transcribe
        self.language = language
        self.inPerson = inPerson
        self.vocabulary = vocabulary
        self.languageWarning = languageWarning
    }

    /// Resolve effective settings for a note, with note frontmatter winning over defaults.
    /// - Parameters:
    ///   - note: The meeting note (may contain per-meeting overrides).
    ///   - defaults: The global default settings provider.
    ///   - globalVocabulary: Enabled global vocabulary entries (e.g. from VocabularyStore).
    public static func resolve(
        note: MeetingNote,
        defaults: any NoteDefaultsProviding,
        globalVocabulary: [String] = []
    ) -> EffectiveMeetingSettings {
        let transcribe = note.transcribe ?? defaults.transcribeByDefault
        let language = note.language ?? defaults.defaultLanguage
        let inPerson = note.inPerson ?? defaults.inPersonByDefault

        // Merge note vocabulary + enabled global entries, deduped case-insensitively.
        // Note entries come first (preferred).
        var seen = Set<String>()
        var merged: [String] = []
        for word in note.vocabulary + globalVocabulary {
            let key = word.lowercased()
            if seen.insert(key).inserted {
                merged.append(word)
            }
        }

        // Warning fires when the global default is a fixed language (not auto-detect).
        let warning: String? = defaults.defaultLanguage != .auto ? languageWarningText : nil

        return EffectiveMeetingSettings(
            transcribe: transcribe,
            language: language,
            inPerson: inPerson,
            vocabulary: merged,
            languageWarning: warning
        )
    }
}
