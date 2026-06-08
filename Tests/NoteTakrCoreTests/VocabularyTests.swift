import XCTest
@testable import NoteTakrCore

final class VocabularyTests: XCTestCase {

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

    // MARK: - Trimming responsibility

    func testPhraseStoredExactly() throws {
        // VocabularyStore stores phrases as-is; trimming is the ViewModel's job.
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

    // MARK: - Helpers

    private func makeVocabStore() -> VocabularyStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VocabTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return VocabularyStore(fileURL: dir.appendingPathComponent("vocabulary.json"))
    }
}
