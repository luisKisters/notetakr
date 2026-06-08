import XCTest
import NoteTakrCore
@testable import NoteTakr

// Automated tests covering MVP-polish flows:
// vocabulary management, mock recording lifecycle,
// note generation, and notification scheduler compile check.
final class MVPPolishTests: XCTestCase {

    // MARK: - Settings / Vocabulary

    func testSettingsVocabularyAdd() throws {
        let store = makeVocabStore()
        let entry = VocabularyEntry(phrase: "SwiftUI")
        try store.save([entry])

        let loaded = try store.load()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].phrase, "SwiftUI")
    }

    func testSettingsVocabularyRemove() throws {
        let store = makeVocabStore()
        let e1 = VocabularyEntry(phrase: "Alpha")
        let e2 = VocabularyEntry(phrase: "Beta")
        try store.save([e1, e2])

        var loaded = try store.load()
        loaded.removeAll { $0.phrase == "Alpha" }
        try store.save(loaded)

        let final_ = try store.load()
        XCTAssertEqual(final_.count, 1)
        XCTAssertEqual(final_[0].phrase, "Beta")
    }

    func testSettingsVocabularyToggle() throws {
        let store = makeVocabStore()
        var entry = VocabularyEntry(phrase: "CoreData")
        entry.isEnabled = true
        try store.save([entry])

        var loaded = try store.load()
        loaded[0].isEnabled = false
        try store.save(loaded)

        let reloaded = try store.load()
        XCTAssertFalse(reloaded[0].isEnabled)
    }

    // MARK: - Mock Recording Start / Stop

    func testStartMockRecording() async throws {
        let manager = makeManager()
        let session = try await manager.startRecording(title: "UI Test Recording")
        XCTAssertEqual(session.status, .recording)
        XCTAssertTrue(manager.isRecording)
    }

    func testStopMockRecording() async throws {
        let manager = makeManager()
        _ = try await manager.startRecording(title: "UI Test Recording")
        let stopped = try await manager.stopRecording()
        XCTAssertEqual(stopped.status, .stopped)
        XCTAssertFalse(manager.isRecording)
    }

    // MARK: - Note Generation

    func testGenerateNoteAndSave() throws {
        let tempDir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = SessionStore(baseURL: tempDir)
        var session = MeetingSession(
            title: "Design Review",
            date: Date(timeIntervalSince1970: 1_700_000_000),
            status: .stopped
        )
        session.transcriptSegments = [
            TranscriptSegment(timestamp: 0, speaker: "Alice", text: "Let's begin."),
        ]
        session.personalNotes = "Action items noted."
        try store.save(session)

        let markdown = MarkdownNoteRenderer.render(session: session)
        XCTAssertTrue(markdown.contains("Design Review"))
        XCTAssertTrue(markdown.contains("Let's begin."))
        XCTAssertTrue(markdown.contains("Action items noted."))

        let noteURL = store.sessionURL(for: session).appendingPathComponent("note.md")
        try markdown.write(to: noteURL, atomically: true, encoding: .utf8)
        XCTAssertTrue(FileManager.default.fileExists(atPath: noteURL.path))

        let onDisk = try String(contentsOf: noteURL, encoding: .utf8)
        XCTAssertEqual(onDisk, markdown)
    }

    // MARK: - Notification Scheduler

    func testNotificationSchedulerInstantiates() {
        let scheduler = MeetingNotificationScheduler()
        XCTAssertNotNil(scheduler)
    }

    func testNotificationSchedulerConstants() {
        XCTAssertEqual(MeetingNotificationScheduler.categoryID, "MEETING_REMINDER")
        XCTAssertEqual(MeetingNotificationScheduler.startRecordingActionID, "START_RECORDING")
    }

    func testNotificationSchedulerSkipsPastEvents() {
        let scheduler = MeetingNotificationScheduler()
        let pastEvent = CalendarEvent(
            id: UUID().uuidString,
            title: "Past Meeting",
            startDate: Date(timeIntervalSinceNow: -3600),
            endDate: Date(timeIntervalSinceNow: -3000)
        )
        // Must not crash — silently skipped because fire date is in the past.
        scheduler.scheduleReminder(for: pastEvent, minutesBefore: 5)
    }

    // MARK: - Privacy Usage Strings

    func testPrivacyUsageDescriptionsExist() throws {
        let infoURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("NoteTakrApp/Info.plist")
        let data = try Data(contentsOf: infoURL)
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])

        for key in ["NSMicrophoneUsageDescription", "NSCalendarsUsageDescription", "NSScreenCaptureUsageDescription"] {
            let value = try XCTUnwrap(plist[key] as? String, "\(key) must exist to avoid TCC crashes")
            XCTAssertFalse(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    // MARK: - Helpers

    private func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MVPPolish-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeVocabStore() -> VocabularyStore {
        let dir = makeTempDir()
        return VocabularyStore(fileURL: dir.appendingPathComponent("vocab.json"))
    }

    private func makeManager() -> RecordingManager {
        let dir = makeTempDir()
        return RecordingManager(store: SessionStore(baseURL: dir), recorder: MockAudioRecorder())
    }
}
