import Foundation
import XCTest
import NoteTakrCore
import NoteTakrKit
@testable import NoteTakrSync

/// A privacy-safe whole-pipeline fixture: valid synthetic mic/system WAVs,
/// multiple speakers, persisted transcript + summary, Obsidian Markdown, and
/// the same cloud payload that later drives the CRM push action.
final class MeetingLifecycleE2ETests: XCTestCase {
    private var root: URL!
    private var sessionsRoot: URL!
    private var obsidianRoot: URL!
    private var spoolRoot: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MeetingLifecycleE2E-\(UUID().uuidString)", isDirectory: true)
        sessionsRoot = root.appendingPathComponent("Sessions", isDirectory: true)
        obsidianRoot = root.appendingPathComponent("Vault/2 Calendar/3 Meeting Notes", isDirectory: true)
        spoolRoot = root.appendingPathComponent("CloudSpool", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testSyntheticRemoteMeetingFlowsFromRecordingToObsidianAndCloud() async throws {
        let sessionStore = SessionStore(baseURL: sessionsRoot)
        let noteStore = NoteStore(root: sessionsRoot)
        let recorder = MockAudioRecorder()
        let recordingManager = RecordingManager(store: sessionStore, recorder: recorder)
        let id = UUID(uuidString: "90909090-9090-9090-9090-909090909090")!
        let startedAt = Self.utcDate(2026, 7, 23, 13, 0)
        let fixtureContact = NoteTakrKit.Participant(
            name: "Mara Fixture",
            email: "notetakr-e2e-contact@example.invalid",
            crm: "crm-fixture-contact-01"
        )

        let input = MeetingSession(
            id: id,
            title: "Synthetic Product Handoff",
            date: startedAt,
            personalNotes: "# Topics\n- Validate the handoff\n- [ ] Mara sends the test brief",
            participants: [
                NoteTakrCore.Participant(
                    name: fixtureContact.name,
                    email: fixtureContact.email,
                    crm: fixtureContact.crm
                ),
                NoteTakrCore.Participant(name: "Noah Fixture", email: "noah@example.invalid"),
            ],
            microphoneEnabled: true,
            systemAudioEnabled: true
        )

        _ = try await recordingManager.startRecording(session: input)
        try noteStore.save(MeetingNote(
            id: id.uuidString,
            title: input.title,
            date: startedAt,
            participants: [
                fixtureContact,
                NoteTakrKit.Participant(name: "Noah Fixture", email: "noah@example.invalid"),
            ],
            location: .meet,
            meetingLink: "https://meet.example.invalid/e2e-room",
            body: input.personalNotes
        ))
        let stopped = try await recordingManager.stopRecording()

        XCTAssertEqual(stopped.audioFilePaths.count, 2)
        XCTAssertEqual(stopped.audioSourceStatuses.filter(\.isPresent).count, 2)
        var recordedAudio: [Data] = []
        for path in stopped.audioFilePaths {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            recordedAudio.append(data)
            XCTAssertEqual(String(decoding: data.prefix(4), as: UTF8.self), "RIFF")
            XCTAssertEqual(String(decoding: data.dropFirst(8).prefix(4), as: UTF8.self), "WAVE")
            XCTAssertEqual(Array(data[20..<24]), [1, 0, 1, 0], "Expected PCM mono audio")
            XCTAssertEqual(Array(data[24..<28]), [128, 62, 0, 0], "Expected a 16 kHz sample rate")
            XCTAssertEqual(Array(data[34..<36]), [16, 0], "Expected 16-bit samples")
            XCTAssertGreaterThan(data.count, 10_000)
        }
        XCTAssertNotEqual(recordedAudio[0], recordedAudio[1], "Mic and system fixtures must differ")

        let engine = ValidatingSyntheticConversationEngine()
        let transcription = TranscriptionService(engine: engine, store: sessionStore)
        var completed = try await transcription.transcribe(
            session: stopped,
            vocabulary: [VocabularyEntry(phrase: "NoteTakr")]
        )
        completed.summary = "The team validated the handoff and assigned the test brief to Mara."
        try sessionStore.save(completed)

        XCTAssertEqual(engine.roles, [.microphone, .systemAudio])
        XCTAssertEqual(engine.validatedSourceCount, 2)
        XCTAssertEqual(Set(completed.transcriptSegments.compactMap(\.speaker)), [
            "Luis Fixture", "Mara Fixture", "Noah Fixture", "Priya Fixture",
        ])

        let note = try XCTUnwrap(noteStore.load(id: id.uuidString))
        let document = ObsidianExportDocument(
            note: note,
            notes: input.personalNotes,
            summary: completed.summary,
            transcript: completed.transcriptSegments.map {
                ObsidianTranscriptSegment(timestamp: $0.timestamp, speaker: $0.speaker, text: $0.text)
            }
        )
        let obsidianURL = try ObsidianExporter().export(document, to: obsidianRoot)
        let obsidianMarkdown = try String(contentsOf: obsidianURL)

        XCTAssertEqual(obsidianURL.lastPathComponent, "2026-07-23 Synthetic Product Handoff.md")
        XCTAssertTrue(obsidianMarkdown.contains("[[Mara Fixture]]"))
        XCTAssertTrue(obsidianMarkdown.contains("## Summary"))
        XCTAssertTrue(obsidianMarkdown.contains("assigned the test brief"))
        XCTAssertTrue(obsidianMarkdown.contains("**[00:05] Mara Fixture:**"))
        XCTAssertTrue(obsidianMarkdown.contains("**[00:17] Priya Fixture:**"))

        let backend = FileSpoolSyncBackend(rootURL: spoolRoot)
        let outbox = SyncOutbox(rootURL: root.appendingPathComponent("Outbox", isDirectory: true))
        let sync = SyncService(
            backend: backend,
            outbox: outbox,
            loadSession: { localID in
                guard let uuid = UUID(uuidString: localID) else { return nil }
                return try sessionStore.load(id: uuid)
            },
            loadNote: { localID in try noteStore.load(id: localID) },
            persistSummary: { _, _, _ in }
        )

        XCTAssertTrue(try sync.markDirty(localId: id.uuidString))
        await sync.runOnce()

        let payloadData = try Data(contentsOf: backend.payloadURL(for: id.uuidString))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(MeetingPayload.self, from: payloadData)
        XCTAssertEqual(payload.localId, id.uuidString)
        XCTAssertEqual(payload.transcriptSegments.count, 5)
        XCTAssertEqual(payload.participants.first?.crm, "crm-fixture-contact-01")
        XCTAssertEqual(payload.participants.first?.email, "notetakr-e2e-contact@example.invalid")
        XCTAssertFalse(payload.contentHash.isEmpty)
        XCTAssertTrue(try outbox.pendingOperations().isEmpty)
    }

    func testOneOnOneFixtureCarriesResolvedNamesIntoObsidianAndCloud() throws {
        let sessionStore = SessionStore(baseURL: sessionsRoot)
        let noteStore = NoteStore(root: sessionsRoot)
        let id = UUID(uuidString: "91919191-9191-9191-9191-919191919191")!
        let startedAt = Self.utcDate(2026, 7, 23, 14, 15)
        var session = MeetingSession(
            id: id,
            title: "One-on-one Speaker Fixture",
            date: startedAt,
            participants: [
                NoteTakrCore.Participant(name: "Luis Kisters"),
                NoteTakrCore.Participant(name: "Theo Fixture", email: "theo@example.invalid"),
            ],
            microphoneEnabled: true,
            systemAudioEnabled: true
        )
        session.transcriptSegments = SpeakerLabelResolver.resolve(
            segments: [
                .init(timestamp: 0, speaker: "Speaker 1 (You)", text: Self.words(18, prefix: "host")),
                .init(timestamp: 7, speaker: "Speaker 2", text: Self.words(60, prefix: "guest")),
            ],
            session: session,
            userName: "Luis",
            inferNamesFromCalendar: true
        )
        session.summary = "Luis and Theo validated the privacy-safe fixture."
        try sessionStore.save(session)

        let note = MeetingNote(
            id: id.uuidString,
            title: session.title,
            date: startedAt,
            participants: [
                NoteTakrKit.Participant(name: "Luis Kisters"),
                NoteTakrKit.Participant(name: "Theo Fixture", email: "theo@example.invalid"),
            ],
            body: "Fixture notes"
        )
        try noteStore.save(note)

        XCTAssertEqual(session.transcriptSegments.map(\.speaker), ["Luis (You)", "Theo Fixture"])

        let exported = try ObsidianExporter().export(
            ObsidianExportDocument(
                note: note,
                notes: note.body,
                summary: session.summary,
                transcript: session.transcriptSegments.map {
                    ObsidianTranscriptSegment(
                        timestamp: $0.timestamp,
                        speaker: $0.speaker,
                        text: $0.text
                    )
                }
            ),
            to: obsidianRoot
        )
        let markdown = try String(contentsOf: exported)
        XCTAssertTrue(markdown.contains("**[00:00] Luis (You):**"))
        XCTAssertTrue(markdown.contains("**[00:07] Theo Fixture:**"))

        let payload = try SyncEnvelope.payload(session: session, note: note)
        XCTAssertEqual(payload.transcriptSegments.map(\.speaker), ["Luis (You)", "Theo Fixture"])
        XCTAssertEqual(payload.participants.last?.email, "theo@example.invalid")
    }

    private static func utcDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return components.date!
    }

    private static func words(_ count: Int, prefix: String) -> String {
        (1...count).map { "\(prefix)\($0)" }.joined(separator: " ")
    }
}

private final class ValidatingSyntheticConversationEngine: TranscriptionEngine, @unchecked Sendable {
    private(set) var roles: [AudioSourceType] = []
    private(set) var validatedSourceCount = 0

    func transcribe(audioURL: URL, vocabulary: [VocabularyEntry]) async throws -> [NoteTakrCore.TranscriptSegment] {
        throw TranscriptionError.transcriptionFailed("The lifecycle fixture uses the role-aware path.")
    }

    func transcribe(
        sources: [TranscriptionSource],
        vocabulary: [VocabularyEntry]
    ) async throws -> [NoteTakrCore.TranscriptSegment] {
        roles = sources.map(\.role)
        XCTAssertEqual(vocabulary.map(\.phrase), ["NoteTakr"])
        for source in sources {
            let data = try Data(contentsOf: source.url)
            XCTAssertEqual(String(decoding: data.prefix(4), as: UTF8.self), "RIFF")
            XCTAssertEqual(String(decoding: data.dropFirst(8).prefix(4), as: UTF8.self), "WAVE")
            XCTAssertGreaterThan(data.count, 10_000)
            validatedSourceCount += 1
        }
        return [
            .init(timestamp: 0, speaker: "Luis Fixture", text: "Let us validate the handoff."),
            .init(timestamp: 5, speaker: "Mara Fixture", text: "I can send the test brief."),
            .init(timestamp: 9, speaker: "Luis Fixture", text: "Great, I will verify the automation."),
            .init(timestamp: 12, speaker: "Noah Fixture", text: "The cloud payload needs the CRM id."),
            .init(timestamp: 17, speaker: "Priya Fixture", text: "The Obsidian note should update automatically."),
        ]
    }
}
