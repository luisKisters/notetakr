import XCTest
@testable import NoteTakrKit

final class NoteStoreTests: XCTestCase {
    private var tempDir: URL!
    private var store: NoteStore!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("NoteStoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        store = NoteStore(root: tempDir)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Create

    func testCreateWritesNoteFile() throws {
        let note = try store.create(title: "Team Standup", date: utcDate(2026, 1, 1, 9, 0))
        XCTAssertFalse(note.id.isEmpty)
        XCTAssertEqual(note.title, "Team Standup")
        let contents = try FileManager.default.contentsOfDirectory(
            at: tempDir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
        )
        XCTAssertEqual(contents.count, 1)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: contents[0].appendingPathComponent("note.md").path)
        )
    }

    func testFolderNameFormat() throws {
        let note = try store.create(title: "Q3 Review: Strategy!", date: utcDate(2026, 6, 10, 14, 0))
        let shortID = String(note.id.prefix(8))
        let contents = try FileManager.default.contentsOfDirectory(
            at: tempDir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
        )
        let folderName = contents[0].lastPathComponent
        XCTAssertTrue(folderName.hasPrefix("2026-06-10_"), "Expected date prefix, got \(folderName)")
        XCTAssertTrue(folderName.contains("Q3-Review-Strategy"), "Expected sanitized title, got \(folderName)")
        XCTAssertTrue(folderName.hasSuffix("_\(shortID)"), "Expected shortID suffix, got \(folderName)")
    }

    // MARK: - Save and Load

    func testSaveAndLoad() throws {
        let created = try store.create(title: "Standup", date: utcDate(2026, 1, 1, 9, 0))
        var modified = created
        modified.body = "Some meeting notes"
        try store.save(modified)
        let loaded = try store.load(id: created.id)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.title, "Standup")
        XCTAssertEqual(loaded?.body, "Some meeting notes")
    }

    func testLoadFromNonExistentDir() throws {
        let emptyStore = NoteStore(root: tempDir.appendingPathComponent("nonexistent"))
        XCTAssertNil(try emptyStore.load(id: "anything"))
    }

    func testLoadUnknownIDReturnsNil() throws {
        _ = try store.create(title: "Note", date: utcDate(2026, 1, 1, 9, 0))
        XCTAssertNil(try store.load(id: "NOTEXIST-0000-0000-0000-000000000000"))
    }

    // MARK: - List

    func testListEmpty() throws {
        XCTAssertTrue(try store.list().isEmpty)
    }

    func testListFromNonExistentDir() throws {
        let emptyStore = NoteStore(root: tempDir.appendingPathComponent("nonexistent"))
        XCTAssertTrue(try emptyStore.list().isEmpty)
    }

    func testListSortedByDateDesc() throws {
        let n1 = try store.create(title: "Standup",  date: utcDate(2026, 1, 1, 9, 0))
        let n2 = try store.create(title: "Retro",    date: utcDate(2026, 1, 2, 9, 0))
        let n3 = try store.create(title: "Planning", date: utcDate(2026, 1, 3, 9, 0))
        let notes = try store.list()
        XCTAssertEqual(notes.count, 3)
        XCTAssertEqual(notes[0].id, n3.id)
        XCTAssertEqual(notes[1].id, n2.id)
        XCTAssertEqual(notes[2].id, n1.id)
    }

    func testListIgnoresFoldersWithoutNoteFile() throws {
        let orphan = tempDir.appendingPathComponent("2026-01-01_no-notes_ABCD1234")
        try FileManager.default.createDirectory(at: orphan, withIntermediateDirectories: false)
        XCTAssertTrue(try store.list().isEmpty)
    }

    // MARK: - Rename

    func testRenameTitleRenamesFolderAndKeepsSiblings() throws {
        let created = try store.create(title: "Old Title", date: utcDate(2026, 3, 1, 10, 0))
        let originalFolders = try FileManager.default.contentsOfDirectory(
            at: tempDir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
        )
        let audioFile = originalFolders[0].appendingPathComponent("recording.m4a")
        try Data("fake audio".utf8).write(to: audioFile)

        var renamed = created
        renamed.title = "New Title"
        try store.save(renamed)

        let newContents = try FileManager.default.contentsOfDirectory(
            at: tempDir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
        )
        XCTAssertEqual(newContents.count, 1)
        let newFolder = newContents[0]
        XCTAssertTrue(
            newFolder.lastPathComponent.contains("New-Title"),
            "Expected renamed folder, got \(newFolder.lastPathComponent)"
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: newFolder.appendingPathComponent("recording.m4a").path),
            "Sibling .m4a file must survive the rename"
        )
    }

    // MARK: - Migration

    func testMigrationFromSessionJson() throws {
        let sessionID = UUID(uuidString: "12345678-1234-1234-1234-1234567890AB")!
        let sessionJSON = """
        {
            "id": "12345678-1234-1234-1234-1234567890AB",
            "title": "Team Standup",
            "date": "2026-03-01T09:00:00Z",
            "status": "completed",
            "transcriptSegments": [],
            "personalNotes": "",
            "audioFilePaths": [],
            "audioSourceStatuses": [],
            "linkedEventID": "CAL-123",
            "linkedEventTitle": "Daily Standup",
            "participants": [
                {"name": "Alice", "email": "alice@example.com"},
                {"name": "Bob"}
            ]
        }
        """
        let folderURL = tempDir.appendingPathComponent(
            "2026-03-01_Team-Standup_\(String(sessionID.uuidString.prefix(8)))"
        )
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: false)
        try Data(sessionJSON.utf8).write(to: folderURL.appendingPathComponent("session.json"))
        try Data("Some body content".utf8).write(to: folderURL.appendingPathComponent("note.md"))

        let note = try store.load(id: sessionID.uuidString)
        XCTAssertNotNil(note)
        XCTAssertEqual(note?.title, "Team Standup")
        XCTAssertEqual(note?.id, sessionID.uuidString)
        XCTAssertEqual(note?.calendarEvent, "CAL-123")
        XCTAssertEqual(note?.participants.count, 2)
        XCTAssertEqual(note?.participants.first?.name, "Alice")
        XCTAssertEqual(note?.participants.first?.email, "alice@example.com")
        XCTAssertEqual(note?.participants.last?.name, "Bob")
        XCTAssertNil(note?.participants.last?.email)
        XCTAssertEqual(note?.body, "Some body content")
    }

    func testMigrationIdempotency() throws {
        let sessionID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let sessionJSON = """
        {
            "id": "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA",
            "title": "Important Meeting",
            "date": "2026-04-01T10:00:00Z",
            "status": "completed",
            "transcriptSegments": [],
            "personalNotes": "",
            "audioFilePaths": [],
            "audioSourceStatuses": []
        }
        """
        let folderURL = tempDir.appendingPathComponent(
            "2026-04-01_Important-Meeting_\(String(sessionID.uuidString.prefix(8)))"
        )
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: false)
        try Data(sessionJSON.utf8).write(to: folderURL.appendingPathComponent("session.json"))
        let noteFile = folderURL.appendingPathComponent("note.md")
        try Data("".utf8).write(to: noteFile)

        let first = try store.load(id: sessionID.uuidString)
        XCTAssertEqual(first?.title, "Important Meeting")

        let noteText = try String(contentsOf: noteFile, encoding: .utf8)
        XCTAssertTrue(noteText.hasPrefix("---"), "note.md should have frontmatter after migration")

        // Corrupt session.json — second load must still succeed via the written frontmatter
        try Data("CORRUPT!".utf8).write(to: folderURL.appendingPathComponent("session.json"))
        let second = try store.load(id: sessionID.uuidString)
        XCTAssertNotNil(second)
        XCTAssertEqual(second?.title, "Important Meeting")
    }

    func testCorruptSessionJsonFallsBackToBodyOnly() throws {
        let folderURL = tempDir.appendingPathComponent("2026-01-01_test_ABCD1234")
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: false)
        try Data("CORRUPT JSON!".utf8).write(to: folderURL.appendingPathComponent("session.json"))
        try Data("Notes without frontmatter".utf8).write(to: folderURL.appendingPathComponent("note.md"))

        let notes = try store.list()
        XCTAssertEqual(notes.count, 1)
        XCTAssertEqual(notes[0].body, "Notes without frontmatter")
        XCTAssertTrue(notes[0].id.isEmpty, "Body-only note should have empty id")
    }

    func testSessionJsonIsNeverModified() throws {
        let sessionID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let sessionJSON = """
        {
            "id": "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB",
            "title": "Review",
            "date": "2026-05-01T14:00:00Z",
            "status": "completed",
            "transcriptSegments": [],
            "personalNotes": "",
            "audioFilePaths": [],
            "audioSourceStatuses": []
        }
        """
        let folderURL = tempDir.appendingPathComponent(
            "2026-05-01_Review_\(String(sessionID.uuidString.prefix(8)))"
        )
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: false)
        let sessionFile = folderURL.appendingPathComponent("session.json")
        try Data(sessionJSON.utf8).write(to: sessionFile)
        try Data("".utf8).write(to: folderURL.appendingPathComponent("note.md"))

        let before = try String(contentsOf: sessionFile, encoding: .utf8)
        _ = try store.load(id: sessionID.uuidString)
        let after = try String(contentsOf: sessionFile, encoding: .utf8)
        XCTAssertEqual(before, after, "session.json must never be modified by NoteStore")
    }

    // MARK: - Sanitize title

    func testSanitizeTitle() {
        XCTAssertEqual(NoteStore.sanitizeTitle("Team Standup"), "Team-Standup")
        XCTAssertEqual(NoteStore.sanitizeTitle(""), "unnamed")
        XCTAssertEqual(NoteStore.sanitizeTitle("!!!"), "unnamed")
        XCTAssertEqual(NoteStore.sanitizeTitle("Q3 Review: Strategy!"), "Q3-Review-Strategy")
        XCTAssertEqual(NoteStore.sanitizeTitle("normal-title_123"), "normal-title_123")
        XCTAssertEqual(NoteStore.sanitizeTitle("  lots   of   spaces  "), "lots-of-spaces")
    }

    // MARK: - Helpers

    private func utcDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day
        c.hour = hour; c.minute = minute; c.second = 0
        c.timeZone = TimeZone(secondsFromGMT: 0)
        return Calendar(identifier: .gregorian).date(from: c)!
    }
}
