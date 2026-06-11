import XCTest
@testable import NoteTakrCore
import NoteTakrKit

final class VocabularyTests: XCTestCase {

    // MARK: - VocabularyStore persistence (macOS-CI subset; full suite in NoteTakrKitTests/VocabularyStoreTests)

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

    func testEnabledEntriesFiltersByIsEnabled() throws {
        let store = makeVocabStore()
        let on  = VocabularyEntry(phrase: "On",  isEnabled: true)
        let off = VocabularyEntry(phrase: "Off", isEnabled: false)
        try store.save([on, off])

        let enabled = try store.enabledEntries()
        XCTAssertEqual(enabled.count, 1)
        XCTAssertEqual(enabled[0].phrase, "On")
    }

    // MARK: - Helpers

    private func makeVocabStore() -> VocabularyStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VocabTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return VocabularyStore(fileURL: dir.appendingPathComponent("vocabulary.json"))
    }
}
