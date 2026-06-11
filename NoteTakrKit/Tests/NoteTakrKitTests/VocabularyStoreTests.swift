import XCTest
@testable import NoteTakrKit

final class VocabularyStoreTests: XCTestCase {

    // MARK: - VocabularyEntry defaults

    func testDefaultEntryIsEnabledWithDefaultWeight() {
        let entry = VocabularyEntry(phrase: "CoreData")
        XCTAssertTrue(entry.isEnabled)
        XCTAssertEqual(entry.boostingWeight, 1.0)
        XCTAssertTrue(entry.aliases.isEmpty)
    }

    func testEntryEquality() {
        let id = UUID()
        let a = VocabularyEntry(id: id, phrase: "Test")
        let b = VocabularyEntry(id: id, phrase: "Test")
        XCTAssertEqual(a, b)
    }

    // MARK: - VocabularyStore persistence

    func testLoadReturnsEmptyWhenFileAbsent() throws {
        let store = makeVocabStore()
        let entries = try store.load()
        XCTAssertTrue(entries.isEmpty)
    }

    func testSaveAndLoadRoundTrip() throws {
        let store = makeVocabStore()
        let entry = VocabularyEntry(phrase: "SwiftUI", aliases: ["swift ui"], boostingWeight: 1.5)
        try store.save([entry])

        let loaded = try store.load()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].phrase, "SwiftUI")
        XCTAssertEqual(loaded[0].aliases, ["swift ui"])
        XCTAssertEqual(loaded[0].boostingWeight, 1.5)
    }

    func testSaveOverwritesPreviousEntries() throws {
        let store = makeVocabStore()
        try store.save([VocabularyEntry(phrase: "Alpha"), VocabularyEntry(phrase: "Beta")])
        try store.save([VocabularyEntry(phrase: "Gamma")])

        let loaded = try store.load()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].phrase, "Gamma")
    }

    func testSaveEmptyListClearsFile() throws {
        let store = makeVocabStore()
        try store.save([VocabularyEntry(phrase: "Foo")])
        try store.save([])

        let loaded = try store.load()
        XCTAssertTrue(loaded.isEmpty)
    }

    func testPhraseStoredExactly() throws {
        let store = makeVocabStore()
        let entry = VocabularyEntry(phrase: "  hello  ")
        try store.save([entry])

        let loaded = try store.load()
        XCTAssertEqual(loaded[0].phrase, "  hello  ")
    }

    // MARK: - enabledEntries filtering

    func testEnabledEntriesFiltersByIsEnabled() throws {
        let store = makeVocabStore()
        let on  = VocabularyEntry(phrase: "On",  isEnabled: true)
        let off = VocabularyEntry(phrase: "Off", isEnabled: false)
        try store.save([on, off])

        let enabled = try store.enabledEntries()
        XCTAssertEqual(enabled.count, 1)
        XCTAssertEqual(enabled[0].phrase, "On")
    }

    func testEnabledEntriesReturnsEmptyWhenAllDisabled() throws {
        let store = makeVocabStore()
        try store.save([
            VocabularyEntry(phrase: "A", isEnabled: false),
            VocabularyEntry(phrase: "B", isEnabled: false),
        ])
        let enabled = try store.enabledEntries()
        XCTAssertTrue(enabled.isEmpty)
    }

    func testEnabledEntriesReturnsAllWhenAllEnabled() throws {
        let store = makeVocabStore()
        try store.save([
            VocabularyEntry(phrase: "X", isEnabled: true),
            VocabularyEntry(phrase: "Y", isEnabled: true),
        ])
        let enabled = try store.enabledEntries()
        XCTAssertEqual(enabled.count, 2)
    }

    // MARK: - addEntry (add, persist/reload, duplicate handling)

    func testAddEntryAppendsAndPersists() throws {
        let store = makeVocabStore()
        try store.addEntry(phrase: "Acme")
        let loaded = try store.load()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].phrase, "Acme")
        XCTAssertTrue(loaded[0].isEnabled)
    }

    func testAddEntryRoundTripAcrossInstances() throws {
        let fileURL = makeVocabStoreURL()
        let store1 = VocabularyStore(fileURL: fileURL)
        try store1.addEntry(phrase: "SwiftData")

        let store2 = VocabularyStore(fileURL: fileURL)
        let loaded = try store2.load()
        XCTAssertEqual(loaded.map { $0.phrase }, ["SwiftData"])
    }

    func testAddEntryDuplicateCaseInsensitiveIsIgnored() throws {
        let store = makeVocabStore()
        try store.addEntry(phrase: "Acme")
        try store.addEntry(phrase: "acme")
        try store.addEntry(phrase: "ACME")
        let loaded = try store.load()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].phrase, "Acme")
    }

    func testAddEntryIgnoresBlankPhrase() throws {
        let store = makeVocabStore()
        try store.addEntry(phrase: "   ")
        try store.addEntry(phrase: "")
        XCTAssertTrue(try store.load().isEmpty)
    }

    func testAddEntryMultiplePhrases() throws {
        let store = makeVocabStore()
        try store.addEntry(phrase: "Alpha")
        try store.addEntry(phrase: "Beta")
        try store.addEntry(phrase: "Gamma")
        let phrases = try store.load().map { $0.phrase }
        XCTAssertEqual(phrases, ["Alpha", "Beta", "Gamma"])
    }

    func testAddEntryPreservesExistingAliasesAndWeight() throws {
        let store = makeVocabStore()
        let existing = VocabularyEntry(phrase: "SwiftUI", aliases: ["swift ui"], boostingWeight: 1.5)
        try store.save([existing])
        try store.addEntry(phrase: "AppKit")
        let loaded = try store.load()
        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded[0].aliases, ["swift ui"])
        XCTAssertEqual(loaded[0].boostingWeight, 1.5)
    }

    // MARK: - Enabled entries reach EffectiveMeetingSettings (adapter boundary)

    func testEnabledEntriesReachEffectiveMeetingSettings() throws {
        let store = makeVocabStore()
        let enabledEntry  = VocabularyEntry(phrase: "Acme",   isEnabled: true)
        let disabledEntry = VocabularyEntry(phrase: "Unused", isEnabled: false)
        try store.save([enabledEntry, disabledEntry])

        let enabledPhrases = try store.enabledEntries().map { $0.phrase }
        let note = MeetingNote(id: "n1", title: "Test", date: Date(timeIntervalSince1970: 0))
        let settings = EffectiveMeetingSettings.resolve(
            note: note,
            defaults: NoopDefaultsProvider(),
            globalVocabulary: enabledPhrases
        )

        XCTAssertTrue(settings.vocabulary.contains("Acme"))
        XCTAssertFalse(settings.vocabulary.contains("Unused"))
    }

    func testDisabledEntriesDoNotReachTranscription() throws {
        let store = makeVocabStore()
        let all = [
            VocabularyEntry(phrase: "On",  isEnabled: true),
            VocabularyEntry(phrase: "Off", isEnabled: false),
        ]
        try store.save(all)

        let enabledPhrases = try store.enabledEntries().map { $0.phrase }
        let note = MeetingNote(id: "n1", title: "Test", date: Date(timeIntervalSince1970: 0))
        let settings = EffectiveMeetingSettings.resolve(
            note: note,
            defaults: NoopDefaultsProvider(),
            globalVocabulary: enabledPhrases
        )

        XCTAssertEqual(settings.vocabulary, ["On"])
    }

    func testPerMeetingVocabMergesWithGlobalVocab() throws {
        let store = makeVocabStore()
        try store.save([VocabularyEntry(phrase: "GlobalTerm", isEnabled: true)])

        let enabledPhrases = try store.enabledEntries().map { $0.phrase }
        let note = MeetingNote(
            id: "n1", title: "Test",
            date: Date(timeIntervalSince1970: 0),
            vocabulary: ["PerMeetingTerm"]
        )
        let settings = EffectiveMeetingSettings.resolve(
            note: note,
            defaults: NoopDefaultsProvider(),
            globalVocabulary: enabledPhrases
        )

        XCTAssertTrue(settings.vocabulary.contains("PerMeetingTerm"))
        XCTAssertTrue(settings.vocabulary.contains("GlobalTerm"))
    }

    func testGlobalVocabDeduplicatedCaseInsensitivelyWithPerMeetingVocab() throws {
        let store = makeVocabStore()
        try store.save([VocabularyEntry(phrase: "Acme", isEnabled: true)])

        let enabledPhrases = try store.enabledEntries().map { $0.phrase }
        let note = MeetingNote(
            id: "n1", title: "Test",
            date: Date(timeIntervalSince1970: 0),
            vocabulary: ["acme"]
        )
        let settings = EffectiveMeetingSettings.resolve(
            note: note,
            defaults: NoopDefaultsProvider(),
            globalVocabulary: enabledPhrases
        )

        XCTAssertEqual(settings.vocabulary.count, 1, "Duplicate 'acme'/'Acme' must be deduped")
    }

    // MARK: - Helpers

    private func makeVocabStoreURL() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VocabStoreTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("vocabulary.json")
    }

    private func makeVocabStore() -> VocabularyStore {
        VocabularyStore(fileURL: makeVocabStoreURL())
    }
}
