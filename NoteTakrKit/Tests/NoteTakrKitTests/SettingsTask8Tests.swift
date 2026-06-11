import XCTest
@testable import NoteTakrKit

// MARK: - GlobalVocabularyStore tests

final class GlobalVocabularyStoreTests: XCTestCase {
    private var tempDir: URL!
    private var storeURL: URL!

    override func setUp() {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("GlobalVocabTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        storeURL = tempDir.appendingPathComponent("vocabulary.json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func makeStore() -> GlobalVocabularyStore {
        GlobalVocabularyStore(fileURL: storeURL)
    }

    func testEmptyWhenFileMissing() {
        XCTAssertTrue(makeStore().load().isEmpty)
    }

    func testAddPersistsAndLoads() throws {
        let s = makeStore()
        try s.add("Acme GmbH")
        let s2 = makeStore()
        XCTAssertEqual(s2.load(), ["Acme GmbH"])
    }

    func testAddMultipleTerms() throws {
        let s = makeStore()
        try s.add("Acme")
        try s.add("FluidAudio")
        try s.add("Parakeet")
        XCTAssertEqual(makeStore().load(), ["Acme", "FluidAudio", "Parakeet"])
    }

    func testRemoveTerm() throws {
        let s = makeStore()
        try s.add("Acme")
        try s.add("FluidAudio")
        try s.remove("Acme")
        let terms = makeStore().load()
        XCTAssertFalse(terms.contains("Acme"))
        XCTAssertTrue(terms.contains("FluidAudio"))
    }

    func testRemoveCaseInsensitive() throws {
        let s = makeStore()
        try s.add("Acme")
        try s.remove("acme")
        XCTAssertTrue(makeStore().load().isEmpty, "remove should be case-insensitive to match add")
    }

    func testRemoveNonExistentTermIsNoOp() throws {
        let s = makeStore()
        try s.add("Acme")
        try s.remove("DoesNotExist")
        XCTAssertEqual(makeStore().load(), ["Acme"])
    }

    func testDuplicateAddIgnoredCaseInsensitive() throws {
        let s = makeStore()
        try s.add("Acme")
        try s.add("acme")
        try s.add("ACME")
        XCTAssertEqual(makeStore().load(), ["Acme"])
    }

    func testEmptyStringIgnored() throws {
        let s = makeStore()
        try s.add("   ")
        XCTAssertTrue(makeStore().load().isEmpty)
    }

    func testSaveAndLoadRoundTrip() throws {
        let s = makeStore()
        let terms = ["Alpha", "Beta", "Gamma"]
        try s.save(terms)
        XCTAssertEqual(makeStore().load(), terms)
    }
}

// MARK: - Per-meeting vocabulary via FrontmatterPresenter

final class PerMeetingVocabularyTests: XCTestCase {
    private var spy: SpyVocabStore!

    override func setUp() {
        spy = SpyVocabStore()
    }

    private func makePresenter(vocab: [String] = []) -> FrontmatterPresenter {
        let note = MeetingNote(
            id: "n1", title: "Standup",
            date: Date(timeIntervalSince1970: 1_718_020_800),
            vocabulary: vocab
        )
        spy.note = note
        return FrontmatterPresenter(
            note: note,
            store: spy,
            now: { Date(timeIntervalSince1970: 1_718_020_800) }
        )
    }

    func testAddTermAppendsAndPersists() throws {
        let p = makePresenter()
        try p.addVocabularyTerm("Acme")
        XCTAssertEqual(spy.note?.vocabulary, ["Acme"])
        XCTAssertTrue(p.note.vocabulary.contains("Acme"))
    }

    func testAddTermDeduplicatesCaseInsensitive() throws {
        let p = makePresenter(vocab: ["Acme"])
        try p.addVocabularyTerm("acme")
        XCTAssertEqual(p.note.vocabulary, ["Acme"])
    }

    func testRemoveTermDeletesAndPersists() throws {
        let p = makePresenter(vocab: ["Acme", "Müller"])
        try p.removeVocabularyTerm("Acme")
        XCTAssertFalse(spy.note?.vocabulary.contains("Acme") ?? false)
        XCTAssertTrue(spy.note?.vocabulary.contains("Müller") ?? false)
    }

    func testAddEmptyTermIsIgnored() throws {
        let p = makePresenter()
        try p.addVocabularyTerm("   ")
        XCTAssertTrue(p.note.vocabulary.isEmpty)
    }
}

// MARK: - AppSettingsStore new fields

final class AppSettingsStoreTask8Tests: XCTestCase {
    private func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppSettingsTask8-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func testDefaultsForNewFields() {
        let store = AppSettingsStore(root: makeTempDir())
        XCTAssertEqual(store.yourName, "")
        XCTAssertTrue(store.inferNamesFromCalendar)
        XCTAssertTrue(store.micEnabled)
        XCTAssertTrue(store.systemAudioEnabled)
        XCTAssertEqual(store.selectedSummaryModelSlug, "")
        XCTAssertTrue(store.autoCheckForUpdates)
        XCTAssertFalse(store.autoDownloadUpdates)
    }

    func testYourNameRoundTrip() {
        let root = makeTempDir()
        let s = AppSettingsStore(root: root)
        s.yourName = "Luis Kisters"
        XCTAssertEqual(AppSettingsStore(root: root).yourName, "Luis Kisters")
    }

    func testInferNamesFromCalendarRoundTrip() {
        let root = makeTempDir()
        let s = AppSettingsStore(root: root)
        s.inferNamesFromCalendar = false
        XCTAssertFalse(AppSettingsStore(root: root).inferNamesFromCalendar)
    }

    func testMicEnabledRoundTrip() {
        let root = makeTempDir()
        let s = AppSettingsStore(root: root)
        s.micEnabled = false
        XCTAssertFalse(AppSettingsStore(root: root).micEnabled)
    }

    func testSystemAudioEnabledRoundTrip() {
        let root = makeTempDir()
        let s = AppSettingsStore(root: root)
        s.systemAudioEnabled = false
        XCTAssertFalse(AppSettingsStore(root: root).systemAudioEnabled)
    }

    func testSelectedSummaryModelSlugRoundTrip() {
        let root = makeTempDir()
        let s = AppSettingsStore(root: root)
        s.selectedSummaryModelSlug = "anthropic/claude-opus-4.7"
        XCTAssertEqual(AppSettingsStore(root: root).selectedSummaryModelSlug, "anthropic/claude-opus-4.7")
    }

    func testAutoCheckForUpdatesRoundTrip() {
        let root = makeTempDir()
        let s = AppSettingsStore(root: root)
        s.autoCheckForUpdates = false
        XCTAssertFalse(AppSettingsStore(root: root).autoCheckForUpdates)
    }

    func testAutoDownloadUpdatesRoundTrip() {
        let root = makeTempDir()
        let s = AppSettingsStore(root: root)
        s.autoDownloadUpdates = true
        XCTAssertTrue(AppSettingsStore(root: root).autoDownloadUpdates)
    }

    func testNewFieldsDoNotBreakExistingPayload() {
        // Verify old keys still round-trip correctly alongside new keys.
        let root = makeTempDir()
        let s = AppSettingsStore(root: root)
        s.transcribeByDefault = false
        s.yourName = "Test"
        let s2 = AppSettingsStore(root: root)
        XCTAssertFalse(s2.transcribeByDefault)
        XCTAssertEqual(s2.yourName, "Test")
    }
}

// MARK: - SettingsTab selection model

final class SettingsTabSelectionTests: XCTestCase {
    func testDefaultValues() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SettingsTabTest-\(UUID().uuidString)")
        let store = AppSettingsStore(root: root)

        // This Meeting tab defaults
        XCTAssertTrue(store.transcribeByDefault)
        XCTAssertFalse(store.inPersonByDefault)
        XCTAssertEqual(store.defaultLanguage, .auto)

        // General tab defaults
        XCTAssertEqual(store.appearance, .glass)
        XCTAssertFalse(store.launchAtLogin)
        XCTAssertNil(store.notesFolderPath)

        // Recording tab defaults
        XCTAssertTrue(store.micEnabled)
        XCTAssertTrue(store.systemAudioEnabled)
        XCTAssertEqual(store.yourName, "")
        XCTAssertTrue(store.inferNamesFromCalendar)

        // Updates tab defaults
        XCTAssertTrue(store.autoCheckForUpdates)
        XCTAssertFalse(store.autoDownloadUpdates)
    }
}

// MARK: - Spy store

private final class SpyVocabStore: NoteStoring {
    var note: MeetingNote?
    func load(id: String) throws -> MeetingNote? { note }
    func save(_ note: MeetingNote) throws { self.note = note }
}
