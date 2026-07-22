import XCTest
@testable import NoteTakrKit

final class RecordingNoteBridgeTests: XCTestCase {

    // MARK: - Test doubles

    private final class SpyStore: NoteStoring {
        func load(id: String) throws -> MeetingNote? { nil }
        func save(_ note: MeetingNote) throws {}
    }

    private final class SpyTranscriptionService: TranscriptionRequesting, @unchecked Sendable {
        enum Behavior {
            case succeed([RawSegment])
            case fail(Error)
        }

        let behavior: Behavior
        private(set) var callCount = 0
        private(set) var capturedNoteID: String?
        private(set) var capturedLanguage: TranscribeLanguage?
        private(set) var capturedVocabulary: [String]?

        init(behavior: Behavior) { self.behavior = behavior }

        func transcribe(noteID: String, language: TranscribeLanguage, vocabulary: [String]) async throws -> [RawSegment] {
            callCount += 1
            capturedNoteID = noteID
            capturedLanguage = language
            capturedVocabulary = vocabulary
            // Yield so the caller can observe the intermediate .transcribing state
            // before this task completes (Swift 6 schedules tasks eagerly).
            await Task.yield()
            switch behavior {
            case .succeed(let segs): return segs
            case .fail(let err): throw err
            }
        }
    }

    private final class SequentialTranscriptionService: TranscriptionRequesting, @unchecked Sendable {
        private let results: [Result<[RawSegment], Error>]
        private var index = 0

        init(results: [Result<[RawSegment], Error>]) { self.results = results }

        func transcribe(noteID: String, language: TranscribeLanguage, vocabulary: [String]) async throws -> [RawSegment] {
            let r = results[min(index, results.count - 1)]
            index += 1
            await Task.yield()
            switch r {
            case .success(let segs): return segs
            case .failure(let err): throw err
            }
        }
    }

    private enum TestError: Error, LocalizedError {
        case failed(String)
        var errorDescription: String? {
            if case .failed(let msg) = self { return msg }
            return nil
        }
    }

    // MARK: - Factory helpers

    private func makeNote(id: String = "note-1") -> MeetingNote {
        MeetingNote(id: id, title: "Test Meeting", date: Date())
    }

    private func makePresenter(
        note: MeetingNote,
        now: @escaping () -> Date = { Date() }
    ) -> FrontmatterPresenter {
        FrontmatterPresenter(note: note, store: SpyStore(), now: now)
    }

    private func makeSettings(
        transcribe: Bool = true,
        language: TranscribeLanguage = .auto,
        vocabulary: [String] = []
    ) -> EffectiveMeetingSettings {
        EffectiveMeetingSettings(transcribe: transcribe, language: language, inPerson: false, vocabulary: vocabulary)
    }

    // MARK: - Start recording

    func testStartRecordingSetsState() {
        let note = makeNote()
        let fp = makePresenter(note: note)
        let bridge = RecordingNoteBridge(
            frontmatterPresenter: fp,
            tabsPresenter: NoteTabsPresenter(),
            settings: makeSettings()
        )

        bridge.startRecording()

        XCTAssertEqual(bridge.state, .recording)
    }

    func testStartRecordingSetsRecordingStartedAt() {
        let t = Date(timeIntervalSinceReferenceDate: 1000)
        let note = makeNote()
        let fp = makePresenter(note: note, now: { t })
        let bridge = RecordingNoteBridge(
            frontmatterPresenter: fp,
            tabsPresenter: NoteTabsPresenter(),
            settings: makeSettings(),
            now: { t }
        )

        bridge.startRecording()

        XCTAssertNotNil(fp.recordingStartedAt)
    }

    func testStartRecordingFiresOnChange() {
        let note = makeNote()
        let fp = makePresenter(note: note)
        let bridge = RecordingNoteBridge(
            frontmatterPresenter: fp,
            tabsPresenter: NoteTabsPresenter(),
            settings: makeSettings()
        )
        var count = 0
        bridge.onChange = { count += 1 }

        bridge.startRecording()

        XCTAssertEqual(count, 1)
    }

    // MARK: - Stop recording: no transcription

    func testStopRecordingClearsRecordingStartedAt() {
        let note = makeNote()
        let fp = makePresenter(note: note)
        let bridge = RecordingNoteBridge(
            frontmatterPresenter: fp,
            tabsPresenter: NoteTabsPresenter(),
            settings: makeSettings()
        )

        bridge.startRecording()
        bridge.stopRecording()

        XCTAssertNil(fp.recordingStartedAt)
    }

    func testStopRecordingTranscribeFalseGoesIdle() {
        let note = makeNote()
        let fp = makePresenter(note: note)
        let spy = SpyTranscriptionService(behavior: .succeed([]))
        let bridge = RecordingNoteBridge(
            frontmatterPresenter: fp,
            tabsPresenter: NoteTabsPresenter(),
            settings: makeSettings(transcribe: false),
            transcriptionService: spy
        )

        bridge.startRecording()
        bridge.stopRecording()

        XCTAssertEqual(bridge.state, .idle)
        XCTAssertEqual(spy.callCount, 0, "Spy must not be called when transcribe=false")
    }

    func testStopRecordingNoServiceGoesIdle() {
        let note = makeNote()
        let fp = makePresenter(note: note)
        let bridge = RecordingNoteBridge(
            frontmatterPresenter: fp,
            tabsPresenter: NoteTabsPresenter(),
            settings: makeSettings(transcribe: true),
            transcriptionService: nil
        )

        bridge.startRecording()
        bridge.stopRecording()

        XCTAssertEqual(bridge.state, .idle)
    }

    // MARK: - Full transition: idle → recording → transcribing → ready

    func testFullTransitionHappyPath() {
        let transcribingExp = expectation(description: "state is transcribing")
        let readyExp = expectation(description: "state is ready")
        let note = makeNote()
        let fp = makePresenter(note: note)
        let tabs = NoteTabsPresenter()
        let segments = [RawSegment(speaker: "Alice", timestamp: 0, text: "Hello")]
        let spy = SpyTranscriptionService(behavior: .succeed(segments))
        let bridge = RecordingNoteBridge(
            frontmatterPresenter: fp,
            tabsPresenter: tabs,
            settings: makeSettings(),
            transcriptionService: spy
        )

        bridge.onChange = {
            switch bridge.state {
            case .transcribing: transcribingExp.fulfill()
            case .ready:        readyExp.fulfill()
            default:            break
            }
        }

        bridge.startRecording()
        XCTAssertEqual(bridge.state, .recording)
        XCTAssertNotNil(fp.recordingStartedAt)

        bridge.stopRecording()
        XCTAssertNil(fp.recordingStartedAt)

        wait(for: [transcribingExp, readyExp], timeout: 2, enforceOrder: true)

        XCTAssertEqual(bridge.state, .ready)
        XCTAssertEqual(spy.callCount, 1)
        if case .segments(let display) = tabs.transcriptState(for: note.id) {
            XCTAssertEqual(display.count, 1)
            XCTAssertEqual(display[0].text, "Hello")
        } else {
            XCTFail("Expected .segments transcript state after happy-path transcription")
        }
    }

    // MARK: - Lifetime: transcription must outlive the external reference

    /// Regression: NotePanelController.recordingStopped() drops its only strong
    /// reference to the bridge immediately after stopRecording(). The transcription
    /// task must still run to completion. With a weak `self` capture the bridge would
    /// deallocate before the task ran, transcription would silently never happen, and
    /// the record pill would hang forever on "Transcribing…".
    func testTranscriptionCompletesAfterExternalReferenceDropped() {
        let note = makeNote()
        let fp = makePresenter(note: note)
        let tabs = NoteTabsPresenter()
        let spy = SpyTranscriptionService(
            behavior: .succeed([RawSegment(speaker: "Alice", timestamp: 0, text: "Hello")])
        )

        let segsExp = expectation(description: "segments set after external ref dropped")
        tabs.onChange = {
            if case .segments = tabs.transcriptState(for: note.id) { segsExp.fulfill() }
        }

        var bridge: RecordingNoteBridge? = RecordingNoteBridge(
            frontmatterPresenter: fp,
            tabsPresenter: tabs,
            settings: makeSettings(),
            transcriptionService: spy
        )
        bridge?.startRecording()
        bridge?.stopRecording()
        bridge = nil // drop the only external strong reference, mirroring the controller

        wait(for: [segsExp], timeout: 2)

        if case .segments(let display) = tabs.transcriptState(for: note.id) {
            XCTAssertEqual(display.first?.text, "Hello")
        } else {
            XCTFail("Transcription must complete even after the external reference is dropped")
        }
        XCTAssertEqual(spy.callCount, 1)
    }

    func testDiscardClearsLiveStateWithoutStartingTranscription() {
        let note = makeNote()
        let fp = makePresenter(note: note)
        let tabs = NoteTabsPresenter()
        let spy = SpyTranscriptionService(
            behavior: .succeed([RawSegment(speaker: nil, timestamp: 0, text: "discarded")])
        )
        let bridge = RecordingNoteBridge(
            frontmatterPresenter: fp,
            tabsPresenter: tabs,
            settings: makeSettings(),
            transcriptionService: spy
        )

        bridge.startRecording()
        bridge.discardRecording()

        XCTAssertEqual(bridge.state, .idle)
        XCTAssertNil(fp.recordingStartedAt)
        XCTAssertEqual(spy.callCount, 0)
        XCTAssertEqual(tabs.transcriptState(for: note.id), .empty)
    }

    // MARK: - Failure path

    func testTranscriptionFailureSurfacesMessage() {
        let failedExp = expectation(description: "state is failed")
        let note = makeNote()
        let fp = makePresenter(note: note)
        let bridge = RecordingNoteBridge(
            frontmatterPresenter: fp,
            tabsPresenter: NoteTabsPresenter(),
            settings: makeSettings(),
            transcriptionService: SpyTranscriptionService(
                behavior: .fail(TestError.failed("network error"))
            )
        )

        bridge.onChange = {
            if case .failed = bridge.state { failedExp.fulfill() }
        }

        bridge.startRecording()
        bridge.stopRecording()

        waitForExpectations(timeout: 2)

        if case .failed(let msg) = bridge.state {
            XCTAssertFalse(msg.isEmpty, "Failure message must be non-empty")
        } else {
            XCTFail("Expected .failed state, got \(bridge.state)")
        }
    }

    func testRetryAfterFailureSucceeds() {
        let failedExp = expectation(description: "first attempt failed")
        let readyExp = expectation(description: "retry succeeded")
        var failedOnce = false

        let service = SequentialTranscriptionService(results: [
            .failure(TestError.failed("first error")),
            .success([RawSegment(speaker: "Bob", timestamp: 5, text: "Retry text")])
        ])
        let note = makeNote()
        let fp = makePresenter(note: note)
        let tabs = NoteTabsPresenter()
        let bridge = RecordingNoteBridge(
            frontmatterPresenter: fp,
            tabsPresenter: tabs,
            settings: makeSettings(),
            transcriptionService: service
        )

        bridge.onChange = {
            switch bridge.state {
            case .failed:
                if !failedOnce {
                    failedOnce = true
                    failedExp.fulfill()
                    bridge.retryTranscription()
                }
            case .ready:
                readyExp.fulfill()
            default:
                break
            }
        }

        bridge.startRecording()
        bridge.stopRecording()

        wait(for: [failedExp, readyExp], timeout: 4, enforceOrder: true)

        XCTAssertEqual(bridge.state, .ready)
        if case .segments(let segs) = tabs.transcriptState(for: note.id) {
            XCTAssertEqual(segs[0].text, "Retry text")
        } else {
            XCTFail("Expected segments in transcript after retry")
        }
    }

    func testRetryIgnoredWhenNotFailed() {
        let note = makeNote()
        let fp = makePresenter(note: note)
        let spy = SpyTranscriptionService(behavior: .succeed([]))
        let bridge = RecordingNoteBridge(
            frontmatterPresenter: fp,
            tabsPresenter: NoteTabsPresenter(),
            settings: makeSettings(),
            transcriptionService: spy
        )

        // In idle state, retryTranscription must be a no-op
        bridge.retryTranscription()

        XCTAssertEqual(spy.callCount, 0)
        XCTAssertEqual(bridge.state, .idle)
    }

    // MARK: - Language and vocabulary passthrough

    func testLanguagePassedToService() {
        let readyExp = expectation(description: "ready")
        let note = makeNote()
        let fp = makePresenter(note: note)
        let spy = SpyTranscriptionService(behavior: .succeed([]))
        let expectedLanguage = TranscribeLanguage.code("fr")
        let bridge = RecordingNoteBridge(
            frontmatterPresenter: fp,
            tabsPresenter: NoteTabsPresenter(),
            settings: makeSettings(language: expectedLanguage),
            transcriptionService: spy
        )

        bridge.onChange = {
            if bridge.state == .ready { readyExp.fulfill() }
        }

        bridge.startRecording()
        bridge.stopRecording()
        waitForExpectations(timeout: 2)

        XCTAssertEqual(spy.capturedLanguage, expectedLanguage)
    }

    func testVocabularyPassedToService() {
        let readyExp = expectation(description: "ready")
        let note = makeNote()
        let fp = makePresenter(note: note)
        let spy = SpyTranscriptionService(behavior: .succeed([]))
        let expectedVocabulary = ["Kubernetes", "Terraform", "CI/CD"]
        let bridge = RecordingNoteBridge(
            frontmatterPresenter: fp,
            tabsPresenter: NoteTabsPresenter(),
            settings: makeSettings(vocabulary: expectedVocabulary),
            transcriptionService: spy
        )

        bridge.onChange = {
            if bridge.state == .ready { readyExp.fulfill() }
        }

        bridge.startRecording()
        bridge.stopRecording()
        waitForExpectations(timeout: 2)

        XCTAssertEqual(spy.capturedVocabulary, expectedVocabulary)
    }

    func testNoteIDPassedToService() {
        let readyExp = expectation(description: "ready")
        let note = makeNote(id: "specific-note-id-42")
        let fp = makePresenter(note: note)
        let spy = SpyTranscriptionService(behavior: .succeed([]))
        let bridge = RecordingNoteBridge(
            frontmatterPresenter: fp,
            tabsPresenter: NoteTabsPresenter(),
            settings: makeSettings(),
            transcriptionService: spy
        )

        bridge.onChange = {
            if bridge.state == .ready { readyExp.fulfill() }
        }

        bridge.startRecording()
        bridge.stopRecording()
        waitForExpectations(timeout: 2)

        XCTAssertEqual(spy.capturedNoteID, "specific-note-id-42")
    }

    // MARK: - Elapsed string matches chip formatting (Task 6)

    func testElapsedStringMatchesChipFormatting() {
        var currentTime = Date(timeIntervalSinceReferenceDate: 5000)
        let note = makeNote()
        let fp = makePresenter(note: note, now: { currentTime })
        let bridge = RecordingNoteBridge(
            frontmatterPresenter: fp,
            tabsPresenter: NoteTabsPresenter(),
            settings: makeSettings(),
            now: { currentTime }
        )

        bridge.startRecording()

        func recordingChipString() -> String? {
            fp.chips.compactMap { chip -> String? in
                if case .recording(let s) = chip { return s }
                return nil
            }.first
        }

        // 0 seconds elapsed
        XCTAssertEqual(recordingChipString(), FrontmatterPresenter.formatRecordingElapsed(0))

        // 73 seconds elapsed (1 min)
        currentTime = Date(timeIntervalSinceReferenceDate: 5073)
        XCTAssertEqual(recordingChipString(), FrontmatterPresenter.formatRecordingElapsed(73))

        // 3723 seconds elapsed (62 min)
        currentTime = Date(timeIntervalSinceReferenceDate: 8723)
        XCTAssertEqual(recordingChipString(), FrontmatterPresenter.formatRecordingElapsed(3723))
    }
}
