import XCTest
import NoteTakrKit
import NoteTakrCore
@testable import NoteTakr

/// Integration test: mock-recorder full cycle with fakes.
/// Verifies: exactly one panel; no legacy window; bridge state transitions;
/// Transcript tab populated; transcribe:false short-circuits.
@MainActor
final class RecordingBridgeIntegrationTests: XCTestCase {

    // MARK: - 1. Exactly one panel, no legacy window

    func testExactlyOnePanelCreated() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let npc = NotePanelController(notesRoot: dir)
        XCTAssertNotNil(npc.panel)
        XCTAssertTrue(npc.panel!.canBecomeKey)
    }

    func testNoLegacyPlainWindowCreatedByController() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        // NotePanelController must only create NSPanel, never a plain NSWindow
        let npc = NotePanelController(notesRoot: dir)
        let p = try XCTUnwrap(npc.panel)
        XCTAssertTrue(p is NSPanel, "Controller must create NSPanel, not plain NSWindow")
    }

    // MARK: - 2. Mock-recorder full cycle: bridge state transitions

    func testRecordingBridgeStartsAndTransitionsToRecording() throws {
        let noteID = UUID().uuidString
        let note = MeetingNote(id: noteID, title: "Test", date: Date())
        let spy = SpyBridgeStore(note: note)
        let fp = FrontmatterPresenter(note: note, store: spy, now: { Date() })
        let settings = EffectiveMeetingSettings(transcribe: false, language: .auto, inPerson: false, vocabulary: [])
        let tabs = NoteTabsPresenter(summaryGenerator: nil, editorFlush: {})

        let bridge = RecordingNoteBridge(
            frontmatterPresenter: fp,
            tabsPresenter: tabs,
            settings: settings,
            transcriptionService: nil,
            now: { Date() }
        )

        XCTAssertEqual(bridge.state, .idle)
        bridge.startRecording()
        XCTAssertEqual(bridge.state, .recording)
        XCTAssertNotNil(fp.recordingStartedAt, "recordingStartedAt should be set")
    }

    func testRecordingBridgeWithTranscriptionPopulatesTranscriptTab() async throws {
        let noteID = UUID().uuidString
        let note = MeetingNote(id: noteID, title: "Meeting", date: Date())
        let spy = SpyBridgeStore(note: note)
        let fp = FrontmatterPresenter(note: note, store: spy, now: { Date() })
        let settings = EffectiveMeetingSettings(transcribe: true, language: .auto, inPerson: false, vocabulary: [])
        let tabs = NoteTabsPresenter(summaryGenerator: nil, editorFlush: {})

        let fakeSegments = [RawSegment(speaker: "Alice", timestamp: 0, text: "Hello")]
        let transcriptionSpy = SpyTranscriptionService(result: .success(fakeSegments))

        let bridge = RecordingNoteBridge(
            frontmatterPresenter: fp,
            tabsPresenter: tabs,
            settings: settings,
            transcriptionService: transcriptionSpy,
            now: { Date() }
        )

        bridge.startRecording()
        bridge.stopRecording()

        // Async: wait for transcription to complete
        try await waitForBridgeReady(bridge, timeout: 2.0)

        XCTAssertEqual(bridge.state, .ready)
        XCTAssertNil(fp.recordingStartedAt, "recordingStartedAt cleared after stop")

        let transcriptState = tabs.transcriptState(for: noteID)
        if case .segments(let segs) = transcriptState {
            XCTAssertEqual(segs.count, 1)
            XCTAssertEqual(segs.first?.text, "Hello")
        } else {
            XCTFail("Expected .segments, got \(transcriptState)")
        }
    }

    func testNoteFileWrittenAfterTranscription() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Create a note via NoteStore
        let noteStore = NoteStore(root: dir)
        let note = try noteStore.create(title: "Mock Meeting", date: Date())
        let noteID = note.id

        // Spy store wraps the real store to track saves
        let trackingStore = TrackingNoteStore(backing: noteStore)
        let fp = FrontmatterPresenter(note: note, store: trackingStore, now: { Date() })
        let settings = EffectiveMeetingSettings(transcribe: true, language: .auto, inPerson: false, vocabulary: [])
        let tabs = NoteTabsPresenter(summaryGenerator: nil, editorFlush: {})

        // SpyTranscription also writes a marker to note.md to simulate AppModel.regenerateNote
        let transcriptionWithWrite = SpyTranscriptionService(result: .success([
            RawSegment(speaker: nil, timestamp: 0, text: "Test segment")
        ]))

        let bridge = RecordingNoteBridge(
            frontmatterPresenter: fp,
            tabsPresenter: tabs,
            settings: settings,
            transcriptionService: transcriptionWithWrite,
            now: { Date() }
        )

        bridge.startRecording()
        bridge.stopRecording()
        try await waitForBridgeReady(bridge, timeout: 2.0)

        XCTAssertEqual(bridge.state, .ready)
        XCTAssertEqual(transcriptionWithWrite.callCount, 1)
        XCTAssertEqual(transcriptionWithWrite.receivedNoteIDs.first, noteID)
    }

    // MARK: - 3. Obsidian export follows editor persistence

    func testEditorChangesRefreshOneStableObsidianFile() throws {
        let root = makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let vault = root.appendingPathComponent("Vault", isDirectory: true)
        let model = AppModel(baseURL: root)
        model.appSettings.obsidianFolderPath = vault.path
        model.appSettings.obsidianFileNameTemplate = "e2e-{{id}}-{{title}}"
        model.appSettings.obsidianTemplate = "# {{title}}\n\n{{notes}}"
        model.appSettings.obsidianExportEnabled = true

        let id = UUID()
        let session = MeetingSession(id: id, title: "Initial title", date: Date())
        try model.store.save(session)
        try model.noteStore.save(MeetingNote(
            id: id.uuidString,
            title: session.title,
            date: session.date,
            body: "Initial notes"
        ))

        model.persistEditorChanges(MeetingNote(
            id: id.uuidString,
            title: "Updated title",
            date: session.date,
            body: "Updated notes from the editor"
        ))

        var exports = try markdownFiles(in: vault)
        XCTAssertEqual(exports.count, 1)
        XCTAssertTrue(exports[0].lastPathComponent.contains("Updated title"))
        XCTAssertTrue(try String(contentsOf: exports[0]).contains("Updated notes from the editor"))

        model.persistEditorChanges(MeetingNote(
            id: id.uuidString,
            title: "Renamed again",
            date: session.date,
            body: "Second automatic update"
        ))

        exports = try markdownFiles(in: vault)
        XCTAssertEqual(exports.count, 1, "Renames must move the stable export instead of duplicating it")
        XCTAssertTrue(exports[0].lastPathComponent.contains("Renamed again"))
        XCTAssertTrue(try String(contentsOf: exports[0]).contains("Second automatic update"))
    }

    func testEditorStillExportsWhenCanonicalSessionUpdateIsUnavailable() throws {
        let root = makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let vault = root.appendingPathComponent("Vault", isDirectory: true)
        let model = AppModel(baseURL: root)
        model.appSettings.obsidianFolderPath = vault.path
        model.appSettings.obsidianFileNameTemplate = "e2e-{{id}}"
        model.appSettings.obsidianTemplate = "# {{title}}\n\n{{notes}}"
        model.appSettings.obsidianExportEnabled = true

        let note = MeetingNote(
            id: UUID().uuidString,
            title: "Recovered editor export",
            date: Date(),
            body: "The NoteStore save remains exportable."
        )
        try model.noteStore.save(note)

        model.persistEditorChanges(note)

        let exported = try XCTUnwrap(markdownFiles(in: vault).first)
        let markdown = try String(contentsOf: exported)
        XCTAssertTrue(markdown.contains("Recovered editor export"))
        XCTAssertTrue(markdown.contains("The NoteStore save remains exportable."))
    }

    // MARK: - 4. transcribe:false short-circuits

    func testTranscribeFalseSkipsTranscription() {
        let noteID = UUID().uuidString
        let note = MeetingNote(id: noteID, title: "No Transcript", date: Date())
        let spy = SpyBridgeStore(note: note)
        let fp = FrontmatterPresenter(note: note, store: spy, now: { Date() })
        let settings = EffectiveMeetingSettings(transcribe: false, language: .auto, inPerson: false, vocabulary: [])
        let tabs = NoteTabsPresenter(summaryGenerator: nil, editorFlush: {})
        let transcriptionSpy = SpyTranscriptionService(result: .success([]))

        let bridge = RecordingNoteBridge(
            frontmatterPresenter: fp,
            tabsPresenter: tabs,
            settings: settings,
            transcriptionService: transcriptionSpy,
            now: { Date() }
        )

        bridge.startRecording()
        bridge.stopRecording()

        XCTAssertEqual(bridge.state, .idle, "With transcribe=false, bridge goes back to idle")
        XCTAssertEqual(transcriptionSpy.callCount, 0, "Transcription service must not be called")
    }

    // MARK: - Helpers

    private func waitForBridgeReady(_ bridge: RecordingNoteBridge, timeout: TimeInterval) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            switch bridge.state {
            case .ready, .failed:
                return
            default:
                try await Task.sleep(nanoseconds: 50_000_000) // 50ms
            }
        }
        // Still not ready/failed after timeout
    }

    private func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RecordingBridgeTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func markdownFiles(in folder: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "md" }
    }
}

// MARK: - Test doubles

private final class SpyTranscriptionService: TranscriptionRequesting, @unchecked Sendable {
    let result: Result<[RawSegment], Error>
    private(set) var callCount = 0
    private(set) var receivedNoteIDs: [String] = []

    init(result: Result<[RawSegment], Error>) {
        self.result = result
    }

    func transcribe(noteID: String, language: TranscribeLanguage, vocabulary: [String]) async throws -> [RawSegment] {
        callCount += 1
        receivedNoteIDs.append(noteID)
        return try result.get()
    }
}

private final class SpyBridgeStore: NoteStoring, @unchecked Sendable {
    private var note: MeetingNote
    private(set) var saveCount = 0

    init(note: MeetingNote) { self.note = note }

    func load(id: String) throws -> MeetingNote? { note.id == id ? note : nil }
    func save(_ note: MeetingNote) throws { saveCount += 1; self.note = note }
}

private final class TrackingNoteStore: NoteStoring, @unchecked Sendable {
    private let backing: NoteStore
    private(set) var savedNoteIDs: [String] = []

    init(backing: NoteStore) { self.backing = backing }

    func load(id: String) throws -> MeetingNote? { try backing.load(id: id) }
    func save(_ note: MeetingNote) throws {
        savedNoteIDs.append(note.id)
        try backing.save(note)
    }
}
