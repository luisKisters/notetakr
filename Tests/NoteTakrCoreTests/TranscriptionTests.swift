import XCTest
@testable import NoteTakrCore
import NoteTakrKit

final class VocabularyEntryTests: XCTestCase {

    func testDefaults() {
        let entry = VocabularyEntry(phrase: "SwiftUI")
        XCTAssertTrue(entry.isEnabled)
        XCTAssertEqual(entry.boostingWeight, 1.0)
        XCTAssertTrue(entry.aliases.isEmpty)
        XCTAssertFalse(entry.id.uuidString.isEmpty)
    }

    func testCustomValues() {
        let entry = VocabularyEntry(
            phrase: "NoteTakr",
            aliases: ["note taker", "notetaker"],
            isEnabled: false,
            boostingWeight: 2.5
        )
        XCTAssertEqual(entry.phrase, "NoteTakr")
        XCTAssertEqual(entry.aliases, ["note taker", "notetaker"])
        XCTAssertFalse(entry.isEnabled)
        XCTAssertEqual(entry.boostingWeight, 2.5)
    }

    func testEquality() {
        let id = UUID()
        let a = VocabularyEntry(id: id, phrase: "SwiftUI")
        let b = VocabularyEntry(id: id, phrase: "SwiftUI")
        XCTAssertEqual(a, b)
    }

    func testInequalityOnDifferentIDs() {
        let a = VocabularyEntry(phrase: "SwiftUI")
        let b = VocabularyEntry(phrase: "SwiftUI")
        XCTAssertNotEqual(a, b)
    }
}

final class VocabularyStoreTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VocabTests-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testPersistAndReload() throws {
        let store = VocabularyStore(fileURL: tempDir.appendingPathComponent("vocab.json"))
        let entries: [VocabularyEntry] = [
            VocabularyEntry(phrase: "NoteTakr", aliases: ["note taker"], isEnabled: true, boostingWeight: 1.5),
            VocabularyEntry(phrase: "AVFoundation", isEnabled: false, boostingWeight: 1.0)
        ]
        try store.save(entries)
        let loaded = try store.load()
        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded[0].phrase, "NoteTakr")
        XCTAssertEqual(loaded[0].aliases, ["note taker"])
        XCTAssertEqual(loaded[0].boostingWeight, 1.5)
        XCTAssertEqual(loaded[1].phrase, "AVFoundation")
        XCTAssertFalse(loaded[1].isEnabled)
    }

    func testEmptyWhenFileAbsent() throws {
        let store = VocabularyStore(fileURL: tempDir.appendingPathComponent("missing/vocab.json"))
        let entries = try store.load()
        XCTAssertTrue(entries.isEmpty)
    }

    func testEnabledEntriesFiltering() throws {
        let store = VocabularyStore(fileURL: tempDir.appendingPathComponent("vocab.json"))
        let entries: [VocabularyEntry] = [
            VocabularyEntry(phrase: "Active", isEnabled: true),
            VocabularyEntry(phrase: "Disabled", isEnabled: false),
            VocabularyEntry(phrase: "AlsoActive", isEnabled: true, boostingWeight: 2.0)
        ]
        try store.save(entries)
        let enabled = try store.enabledEntries()
        XCTAssertEqual(enabled.count, 2)
        XCTAssertTrue(enabled.allSatisfy { $0.isEnabled })
        XCTAssertFalse(enabled.contains { $0.phrase == "Disabled" })
    }

    func testOverwritePersists() throws {
        let store = VocabularyStore(fileURL: tempDir.appendingPathComponent("vocab.json"))
        try store.save([VocabularyEntry(phrase: "First")])
        try store.save([VocabularyEntry(phrase: "Second")])
        let loaded = try store.load()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].phrase, "Second")
    }
}

final class MarkdownNoteRendererTests: XCTestCase {

    func testFullRendering() {
        var session = MeetingSession(title: "Sprint Planning", date: Date(timeIntervalSince1970: 0))
        session.personalNotes = "Key decisions made."
        session.audioFilePaths = ["/recordings/microphone.wav"]
        session.transcriptSegments = [
            TranscriptSegment(timestamp: 0, speaker: "Alice", text: "Let's start."),
            TranscriptSegment(timestamp: 65, text: "Item discussed.")
        ]
        let md = MarkdownNoteRenderer.render(session: session)
        XCTAssertTrue(md.contains("# Sprint Planning"))
        XCTAssertTrue(md.contains("**Date:**"))
        XCTAssertTrue(md.contains("## Audio Files"))
        XCTAssertTrue(md.contains("microphone.wav"))
        XCTAssertTrue(md.contains("## Personal Notes"))
        XCTAssertTrue(md.contains("Key decisions made."))
        XCTAssertTrue(md.contains("## Transcript"))
        XCTAssertTrue(md.contains("[0:00]"))
        XCTAssertTrue(md.contains("Alice"))
        XCTAssertTrue(md.contains("[1:05]"))
    }

    func testNoTranscriptSectionWhenEmpty() {
        let session = MeetingSession(title: "Quick Call", date: Date())
        let md = MarkdownNoteRenderer.render(session: session)
        XCTAssertFalse(md.contains("## Transcript"))
    }

    func testNoPersonalNotesSectionWhenEmpty() {
        var session = MeetingSession(title: "Quick Call", date: Date())
        session.transcriptSegments = [TranscriptSegment(timestamp: 0, text: "Hi")]
        let md = MarkdownNoteRenderer.render(session: session)
        XCTAssertFalse(md.contains("## Personal Notes"))
        XCTAssertTrue(md.contains("## Transcript"))
    }

    func testNoAudioFilesSectionWhenEmpty() {
        let session = MeetingSession(title: "Call", date: Date())
        let md = MarkdownNoteRenderer.render(session: session)
        XCTAssertFalse(md.contains("## Audio Files"))
    }

    func testTimestampFormatting() {
        var session = MeetingSession(title: "Call", date: Date())
        session.transcriptSegments = [
            TranscriptSegment(timestamp: 0, text: "Start"),
            TranscriptSegment(timestamp: 90, text: "At ninety seconds"),
            TranscriptSegment(timestamp: 3661, text: "Over an hour")
        ]
        let md = MarkdownNoteRenderer.render(session: session)
        XCTAssertTrue(md.contains("[0:00]"))
        XCTAssertTrue(md.contains("[1:30]"))
        XCTAssertTrue(md.contains("[61:01]"))
    }

    func testStatusIncluded() {
        var session = MeetingSession(title: "Call", date: Date())
        session.status = .stopped
        let md = MarkdownNoteRenderer.render(session: session)
        XCTAssertTrue(md.contains("stopped"))
    }

    func testAudioSourceStatusesSectionPresent() {
        var session = MeetingSession(title: "Call", date: Date())
        session.audioSourceStatuses = [
            AudioSourceStatus(source: .microphone, fileSizeBytes: 2_097_152, durationSeconds: 754),
            AudioSourceStatus(source: .systemAudio, fileSizeBytes: 1_048_576, durationSeconds: 754)
        ]
        let md = MarkdownNoteRenderer.render(session: session)
        XCTAssertTrue(md.contains("## Audio Sources"))
        XCTAssertTrue(md.contains("Microphone"))
        XCTAssertTrue(md.contains("System Audio"))
        XCTAssertTrue(md.contains("Captured"))
        XCTAssertTrue(md.contains("12:34"))
        XCTAssertFalse(md.contains("## Audio Files"))
    }

    func testMissingAudioSourceWithReason() {
        var session = MeetingSession(title: "Call", date: Date())
        session.audioSourceStatuses = [
            AudioSourceStatus(source: .microphone, fileSizeBytes: 512_000, durationSeconds: 60),
            AudioSourceStatus(source: .systemAudio, missingReason: "permission not granted")
        ]
        let md = MarkdownNoteRenderer.render(session: session)
        XCTAssertTrue(md.contains("## Audio Sources"))
        XCTAssertTrue(md.contains("Not captured — permission not granted"))
    }

    func testAudioSourceStatusesWithNoDetailShowsCaptured() {
        var session = MeetingSession(title: "Call", date: Date())
        session.audioSourceStatuses = [
            AudioSourceStatus(source: .microphone, fileSizeBytes: 1024)
        ]
        let md = MarkdownNoteRenderer.render(session: session)
        XCTAssertTrue(md.contains("Captured ("))
    }

    func testAudioSourceStatusesTakePrecedenceOverAudioFilePaths() {
        var session = MeetingSession(title: "Call", date: Date())
        session.audioFilePaths = ["/recordings/microphone.m4a"]
        session.audioSourceStatuses = [
            AudioSourceStatus(source: .microphone, fileSizeBytes: 1024, durationSeconds: 30)
        ]
        let md = MarkdownNoteRenderer.render(session: session)
        XCTAssertTrue(md.contains("## Audio Sources"))
        XCTAssertFalse(md.contains("## Audio Files"))
    }

    func testMissingSourceWithNoReasonUsesDefault() {
        var session = MeetingSession(title: "Call", date: Date())
        session.audioSourceStatuses = [
            AudioSourceStatus(source: .systemAudio)
        ]
        let md = MarkdownNoteRenderer.render(session: session)
        XCTAssertTrue(md.contains("Not captured"))
        XCTAssertFalse(md.contains("Not captured — Not captured"))
    }
}

final class MockTranscriptionEngineTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TranscriptionTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testReturnsFixtureSegments() async throws {
        let audioURL = tempDir.appendingPathComponent("audio.wav")
        try Data("RIFF fixture".utf8).write(to: audioURL)
        let engine = MockTranscriptionEngine()
        let segments = try await engine.transcribe(audioURL: audioURL, vocabulary: [])
        XCTAssertEqual(segments.count, 3)
        XCTAssertEqual(segments[0].speaker, "Alice")
        XCTAssertEqual(segments[0].text, "Let's get started.")
    }

    func testFailsWhenConfigured() async throws {
        let audioURL = tempDir.appendingPathComponent("audio.wav")
        try Data().write(to: audioURL)
        let engine = MockTranscriptionEngine()
        engine.shouldFail = true
        do {
            _ = try await engine.transcribe(audioURL: audioURL, vocabulary: [])
            XCTFail("Expected transcription failure")
        } catch TranscriptionError.transcriptionFailed {
            // Expected
        }
    }

    func testThrowsForMissingFile() async {
        let engine = MockTranscriptionEngine()
        let audioURL = URL(fileURLWithPath: "/nonexistent/missing.wav")
        do {
            _ = try await engine.transcribe(audioURL: audioURL, vocabulary: [])
            XCTFail("Expected audioFileNotFound error")
        } catch TranscriptionError.audioFileNotFound {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testPassesThroughVocabulary() async throws {
        let audioURL = tempDir.appendingPathComponent("audio.wav")
        try Data("RIFF".utf8).write(to: audioURL)
        let entry = VocabularyEntry(phrase: "SwiftUI", isEnabled: true, boostingWeight: 2.0)
        let engine = MockTranscriptionEngine()
        _ = try await engine.transcribe(audioURL: audioURL, vocabulary: [entry])
        XCTAssertEqual(engine.lastVocabulary.count, 1)
        XCTAssertEqual(engine.lastVocabulary[0].phrase, "SwiftUI")
        XCTAssertEqual(engine.lastVocabulary[0].boostingWeight, 2.0)
    }

    func testCallCountTracked() async throws {
        let audioURL = tempDir.appendingPathComponent("audio.wav")
        try Data("RIFF".utf8).write(to: audioURL)
        let engine = MockTranscriptionEngine()
        XCTAssertEqual(engine.transcribeCallCount, 0)
        _ = try await engine.transcribe(audioURL: audioURL, vocabulary: [])
        _ = try await engine.transcribe(audioURL: audioURL, vocabulary: [])
        XCTAssertEqual(engine.transcribeCallCount, 2)
    }

    func testCustomFixtureSegments() async throws {
        let audioURL = tempDir.appendingPathComponent("audio.wav")
        try Data("RIFF".utf8).write(to: audioURL)
        let custom = [TranscriptSegment(timestamp: 10, speaker: "Charlie", text: "Custom text")]
        let engine = MockTranscriptionEngine(fixtureSegments: custom)
        let result = try await engine.transcribe(audioURL: audioURL, vocabulary: [])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].speaker, "Charlie")
    }
}
