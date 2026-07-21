import XCTest
@testable import NoteTakrKit

final class AppSettingsStoreTests: XCTestCase {

    // MARK: - Helpers

    private func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("NoteTakrKitTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeStore(at root: URL) -> AppSettingsStore {
        AppSettingsStore(root: root)
    }

    // MARK: - Default values when no file exists

    func testDefaultsWhenFileMissing() {
        let root = makeTempDir()
        let store = makeStore(at: root)
        XCTAssertTrue(store.transcribeByDefault)
        XCTAssertEqual(store.defaultLanguage, .auto)
        XCTAssertFalse(store.inPersonByDefault)
        XCTAssertEqual(store.appearance, .glass)
        XCTAssertEqual(store.hotkey.displayString, "⌃⌥⌘N")
        XCTAssertEqual(store.recordingHotkey.displayString, "⌃⌥⌘R")
        XCTAssertFalse(store.launchAtLogin)
        XCTAssertNil(store.notesFolderPath)
        XCTAssertFalse(store.localOnlyByDefault)
    }

    // MARK: - Persistence round-trip

    func testRoundTrip() throws {
        let root = makeTempDir()
        let store = makeStore(at: root)
        store.transcribeByDefault = false
        store.defaultLanguage = .code("de")
        store.inPersonByDefault = true
        store.appearance = .dark
        store.hotkey = try HotkeyCombo.parse("⌃⌥⌘P")
        store.recordingHotkey = try HotkeyCombo.parse("⌃⌥⌘R")
        store.launchAtLogin = true
        store.notesFolderPath = "/Users/me/Notes"
        store.localOnlyByDefault = true

        let store2 = makeStore(at: root)
        XCTAssertFalse(store2.transcribeByDefault)
        XCTAssertEqual(store2.defaultLanguage, .code("de"))
        XCTAssertTrue(store2.inPersonByDefault)
        XCTAssertEqual(store2.appearance, .dark)
        XCTAssertEqual(store2.hotkey.displayString, "⌃⌥⌘P")
        XCTAssertEqual(store2.recordingHotkey.displayString, "⌃⌥⌘R")
        XCTAssertTrue(store2.launchAtLogin)
        XCTAssertEqual(store2.notesFolderPath, "/Users/me/Notes")
        XCTAssertTrue(store2.localOnlyByDefault)
    }

    func testNotesFolderPathRoundTrips() {
        let root = makeTempDir()
        let store = makeStore(at: root)
        store.notesFolderPath = "/tmp/meetings"
        let store2 = makeStore(at: root)
        XCTAssertEqual(store2.notesFolderPath, "/tmp/meetings")
    }

    func testNotesFolderPathNilPersistedCorrectly() {
        let root = makeTempDir()
        let store = makeStore(at: root)
        // default is nil; persist then reload
        let store2 = makeStore(at: root)
        XCTAssertNil(store2.notesFolderPath)
        _ = store  // silence unused warning
    }

    // MARK: - Defaults when file is corrupt

    func testCorruptFileUsesDefaults() throws {
        let root = makeTempDir()
        let fileURL = root.appendingPathComponent("settings.json")
        try Data("not json at all {{{".utf8).write(to: fileURL)
        let store = makeStore(at: root)
        XCTAssertTrue(store.transcribeByDefault)
        XCTAssertEqual(store.defaultLanguage, .auto)
    }

    // MARK: - Appearance enum all cases persist

    func testAllAppearancesRoundTrip() {
        for appearance in Appearance.allCases {
            let root = makeTempDir()
            let store = makeStore(at: root)
            store.appearance = appearance
            let store2 = makeStore(at: root)
            XCTAssertEqual(store2.appearance, appearance, "Failed for appearance: \(appearance)")
        }
    }

    // MARK: - NoteDefaultsProviding conformance

    func testConformsToNoteDefaultsProviding() {
        let root = makeTempDir()
        let store: any NoteDefaultsProviding = makeStore(at: root)
        XCTAssertTrue(store.transcribeByDefault)
        XCTAssertEqual(store.defaultLanguage, .auto)
        XCTAssertFalse(store.inPersonByDefault)
        XCTAssertFalse(store.localOnlyByDefault)
    }
}

// MARK: - EffectiveMeetingSettingsTests

final class EffectiveMeetingSettingsTests: XCTestCase {

    private func makeNote(
        id: String = "A",
        title: String = "Standup",
        date: Date = Date(timeIntervalSince1970: 1_718_020_800),
        transcribe: Bool? = nil,
        language: TranscribeLanguage? = nil,
        inPerson: Bool? = nil,
        vocabulary: [String] = []
    ) -> MeetingNote {
        MeetingNote(
            id: id, title: title, date: date,
            inPerson: inPerson, transcribe: transcribe,
            language: language, vocabulary: vocabulary
        )
    }

    struct StubDefaults: NoteDefaultsProviding {
        var transcribeByDefault: Bool
        var defaultLanguage: TranscribeLanguage
        var inPersonByDefault: Bool
        var localOnlyByDefault: Bool
        init(
            transcribeByDefault: Bool = true,
            defaultLanguage: TranscribeLanguage = .auto,
            inPersonByDefault: Bool = false,
            localOnlyByDefault: Bool = false
        ) {
            self.transcribeByDefault = transcribeByDefault
            self.defaultLanguage = defaultLanguage
            self.inPersonByDefault = inPersonByDefault
            self.localOnlyByDefault = localOnlyByDefault
        }
    }

    // MARK: - Note frontmatter wins over defaults

    func testNoteTranscribeOverridesDefault() {
        let note = makeNote(transcribe: false)
        let defaults = StubDefaults(transcribeByDefault: true)
        let effective = EffectiveMeetingSettings.resolve(note: note, defaults: defaults)
        XCTAssertFalse(effective.transcribe)
    }

    func testDefaultTranscribeWhenNoteHasNone() {
        let note = makeNote(transcribe: nil)
        let defaults = StubDefaults(transcribeByDefault: false)
        let effective = EffectiveMeetingSettings.resolve(note: note, defaults: defaults)
        XCTAssertFalse(effective.transcribe)
    }

    func testNoteLanguageOverridesDefault() {
        let note = makeNote(language: .code("fr"))
        let defaults = StubDefaults(defaultLanguage: .code("de"))
        let effective = EffectiveMeetingSettings.resolve(note: note, defaults: defaults)
        XCTAssertEqual(effective.language, .code("fr"))
    }

    func testDefaultLanguageWhenNoteHasNone() {
        let note = makeNote(language: nil)
        let defaults = StubDefaults(defaultLanguage: .code("es"))
        let effective = EffectiveMeetingSettings.resolve(note: note, defaults: defaults)
        XCTAssertEqual(effective.language, .code("es"))
    }

    func testNoteInPersonOverridesDefault() {
        let note = makeNote(inPerson: true)
        let defaults = StubDefaults(inPersonByDefault: false)
        let effective = EffectiveMeetingSettings.resolve(note: note, defaults: defaults)
        XCTAssertTrue(effective.inPerson)
    }

    func testDefaultInPersonWhenNoteHasNone() {
        let note = makeNote(inPerson: nil)
        let defaults = StubDefaults(inPersonByDefault: true)
        let effective = EffectiveMeetingSettings.resolve(note: note, defaults: defaults)
        XCTAssertTrue(effective.inPerson)
    }

    // MARK: - Warning rule

    func testNoWarningWhenDefaultLanguageIsAuto() {
        let note = makeNote()
        let defaults = StubDefaults(defaultLanguage: .auto)
        let effective = EffectiveMeetingSettings.resolve(note: note, defaults: defaults)
        XCTAssertNil(effective.languageWarning)
    }

    func testWarningWhenDefaultLanguageIsFixed() {
        let note = makeNote()
        let defaults = StubDefaults(defaultLanguage: .code("de"))
        let effective = EffectiveMeetingSettings.resolve(note: note, defaults: defaults)
        XCTAssertEqual(effective.languageWarning, EffectiveMeetingSettings.languageWarningText)
    }

    func testWarningTextIsExact() {
        XCTAssertEqual(
            EffectiveMeetingSettings.languageWarningText,
            "Meetings in any other language will be transcribed incorrectly. Auto-detect is recommended."
        )
    }

    // MARK: - Vocabulary merge & dedup

    func testVocabularyMergeNoteFirst() {
        let note = makeNote(vocabulary: ["Acme", "Müller"])
        let defaults = StubDefaults()
        let effective = EffectiveMeetingSettings.resolve(
            note: note, defaults: defaults, globalVocabulary: ["Parakeet", "Müller"]
        )
        // "Müller" is in both — should appear only once (note version wins)
        XCTAssertEqual(effective.vocabulary, ["Acme", "Müller", "Parakeet"])
    }

    func testVocabularyDedupCaseInsensitive() {
        let note = makeNote(vocabulary: ["Acme"])
        let defaults = StubDefaults()
        let effective = EffectiveMeetingSettings.resolve(
            note: note, defaults: defaults, globalVocabulary: ["acme", "ACME", "NoteTakr"]
        )
        // All "acme" variants deduplicated; note's "Acme" wins
        XCTAssertEqual(effective.vocabulary, ["Acme", "NoteTakr"])
    }

    func testVocabularyEmptyNoteAndEmptyGlobal() {
        let note = makeNote(vocabulary: [])
        let defaults = StubDefaults()
        let effective = EffectiveMeetingSettings.resolve(note: note, defaults: defaults)
        XCTAssertTrue(effective.vocabulary.isEmpty)
    }

    func testVocabularyOnlyGlobal() {
        let note = makeNote(vocabulary: [])
        let defaults = StubDefaults()
        let effective = EffectiveMeetingSettings.resolve(
            note: note, defaults: defaults, globalVocabulary: ["FluidAudio"]
        )
        XCTAssertEqual(effective.vocabulary, ["FluidAudio"])
    }

    func testVocabularyOnlyNote() {
        let note = makeNote(vocabulary: ["Raycast"])
        let defaults = StubDefaults()
        let effective = EffectiveMeetingSettings.resolve(note: note, defaults: defaults)
        XCTAssertEqual(effective.vocabulary, ["Raycast"])
    }

    // MARK: - Full resolution matrix

    func testAllDefaultsNoNoteOverrides() {
        let note = makeNote()
        let defaults = StubDefaults()
        let effective = EffectiveMeetingSettings.resolve(note: note, defaults: defaults)
        XCTAssertTrue(effective.transcribe)
        XCTAssertEqual(effective.language, .auto)
        XCTAssertFalse(effective.inPerson)
        XCTAssertTrue(effective.vocabulary.isEmpty)
        XCTAssertNil(effective.languageWarning)
    }

    func testAllNoteOverridesApplied() {
        let note = makeNote(transcribe: false, language: .code("ja"), inPerson: true, vocabulary: ["Tokyo"])
        let defaults = StubDefaults(transcribeByDefault: true, defaultLanguage: .code("de"), inPersonByDefault: false)
        let effective = EffectiveMeetingSettings.resolve(note: note, defaults: defaults)
        XCTAssertFalse(effective.transcribe)
        XCTAssertEqual(effective.language, .code("ja"))
        XCTAssertTrue(effective.inPerson)
        XCTAssertEqual(effective.vocabulary, ["Tokyo"])
        // Warning: defaultLanguage is "de" (not auto) → warning present
        XCTAssertNotNil(effective.languageWarning)
    }

    // MARK: - New-note inheritance (SwitcherViewModel createNote)

    func testCreateNoteFromEventMaterializesDefaults() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("NoteTakrKitTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let settingsStore = AppSettingsStore(root: root)
        settingsStore.transcribeByDefault = false
        settingsStore.defaultLanguage = TranscribeLanguage.code("fr")
        settingsStore.inPersonByDefault = true

        let spy = MemoryNoteStore()

        let event = UpcomingEvent(
            id: "evt-1",
            title: "Kickoff",
            start: Date(timeIntervalSince1970: 1_718_100_000),
            end: Date(timeIntervalSince1970: 1_718_103_600),
            participants: [Participant(name: "Alice")]
        )

        let vm = SwitcherViewModel(
            noteListProvider: spy,
            eventsProvider: SettingsFixedEventsProvider(events: [event]),
            now: { Date(timeIntervalSince1970: 1_718_020_800) },
            store: spy,
            defaultsProvider: settingsStore
        )

        let created = try vm.createNote(from: event)
        XCTAssertEqual(created.transcribe, false)
        XCTAssertEqual(created.language, TranscribeLanguage.code("fr"))
        XCTAssertEqual(created.inPerson, true)
        XCTAssertEqual(created.title, "Kickoff")
    }
}

// MARK: - Test helpers

private final class MemoryNoteStore: NoteStoring, NoteListProviding {
    var notes: [MeetingNote] = []

    func listNotes() -> [MeetingNote] { notes }
    func load(id: String) throws -> MeetingNote? { notes.first { $0.id == id } }
    func save(_ note: MeetingNote) throws {
        notes.removeAll { $0.id == note.id }
        notes.append(note)
    }
}

private struct SettingsFixedEventsProvider: UpcomingEventsProviding {
    let events: [UpcomingEvent]
    func listEvents() -> [UpcomingEvent] { events }
}
