import Combine
import XCTest
import NoteTakrCore
import NoteTakrKit
@testable import NoteTakr

@MainActor
final class NoteTabsBridgeTests: XCTestCase {
    var cancellables = Set<AnyCancellable>()

    override func tearDown() {
        super.tearDown()
        cancellables.removeAll()
    }

    // MARK: - 1. Presenter wiring with a fake SummaryGenerating

    func testGenerateSummaryTransitionsGeneratingThenReady() {
        let gen = ControlledSummaryGenerator()
        let presenter = NoteTabsPresenter(summaryGenerator: gen)
        let bridge = NoteTabsBridge(presenter: presenter)
        bridge.load(noteID: "test-note")

        let readyExp = expectation(description: "bridge summaryState becomes ready")
        bridge.$summaryState.sink { state in
            if case .ready = state { readyExp.fulfill() }
        }.store(in: &cancellables)

        bridge.generateSummary()
        XCTAssertEqual(presenter.summaryState(for: "test-note"), .generating)
        gen.complete(with: "Test summary")

        waitForExpectations(timeout: 2)
        if case .ready(let text) = bridge.summaryState {
            XCTAssertEqual(text, "Test summary")
        } else {
            XCTFail("Expected .ready state, got \(bridge.summaryState)")
        }
    }

    func testGenerateSummaryFailureReflectedOnBridge() {
        let gen = ImmediateSummaryGenerator(result: .failure(FakeError.network))
        let presenter = NoteTabsPresenter(summaryGenerator: gen)
        let bridge = NoteTabsBridge(presenter: presenter)
        bridge.load(noteID: "test-note")

        let failedExp = expectation(description: "bridge summaryState becomes failed")
        bridge.$summaryState.sink { state in
            if case .failed = state { failedExp.fulfill() }
        }.store(in: &cancellables)

        bridge.generateSummary()
        waitForExpectations(timeout: 2)

        if case .failed(let msg) = bridge.summaryState {
            XCTAssertFalse(msg.isEmpty)
        } else {
            XCTFail("Expected .failed state, got \(bridge.summaryState)")
        }
    }

    func testBridgeSelectTabUpdatesPublishedProperty() throws {
        let presenter = NoteTabsPresenter()
        let bridge = NoteTabsBridge(presenter: presenter)
        bridge.load(noteID: "note-1")

        bridge.selectTab(.summary)
        XCTAssertEqual(bridge.selectedTab, .summary)

        bridge.selectTab(.transcript)
        XCTAssertEqual(bridge.selectedTab, .transcript)

        bridge.selectTab(.privateNotes)
        XCTAssertEqual(bridge.selectedTab, .privateNotes)
    }

    // MARK: - 2. Transcript mapping from a fixture MeetingSession

    func testTranscriptMappingFromMeetingSession() {
        let session = MeetingSession(
            title: "Design Review",
            date: Date(),
            transcriptSegments: [
                TranscriptSegment(timestamp: 0, speaker: "Alice", text: "Hello"),
                TranscriptSegment(timestamp: 3, speaker: "Alice", text: "World"),
                TranscriptSegment(timestamp: 10, speaker: "Bob", text: "Hi there"),
            ]
        )

        let rawSegments = session.transcriptSegments.map { seg in
            RawSegment(speaker: seg.speaker, timestamp: seg.timestamp, text: seg.text)
        }

        let grouped = NoteTabsPresenter.groupSegments(rawSegments)
        XCTAssertEqual(grouped.count, 2, "Alice's consecutive segments should merge")
        XCTAssertEqual(grouped[0].speaker, "Alice")
        XCTAssertEqual(grouped[0].startStamp, "0:00")
        XCTAssertEqual(grouped[0].text, "Hello World")
        XCTAssertEqual(grouped[1].speaker, "Bob")
        XCTAssertEqual(grouped[1].startStamp, "0:10")
        XCTAssertEqual(grouped[1].text, "Hi there")
    }

    func testTranscriptMappingNilSpeakers() {
        let session = MeetingSession(
            title: "Unknown speakers",
            date: Date(),
            transcriptSegments: [
                TranscriptSegment(timestamp: 0, speaker: nil, text: "First"),
                TranscriptSegment(timestamp: 5, speaker: nil, text: "Second"),
                TranscriptSegment(timestamp: 10, speaker: "Alice", text: "Named"),
            ]
        )
        let rawSegments = session.transcriptSegments.map { seg in
            RawSegment(speaker: seg.speaker, timestamp: seg.timestamp, text: seg.text)
        }
        let grouped = NoteTabsPresenter.groupSegments(rawSegments)
        XCTAssertEqual(grouped.count, 2)
        XCTAssertNil(grouped[0].speaker)
        XCTAssertEqual(grouped[0].text, "First Second")
        XCTAssertEqual(grouped[1].speaker, "Alice")
    }

    func testEmptySessionProducesEmptyTranscript() {
        let session = MeetingSession(title: "Empty", date: Date(), transcriptSegments: [])
        let rawSegments = session.transcriptSegments.map { seg in
            RawSegment(speaker: seg.speaker, timestamp: seg.timestamp, text: seg.text)
        }
        let presenter = NoteTabsPresenter()
        presenter.setSegments(rawSegments, for: "empty-note")
        XCTAssertEqual(presenter.transcriptState(for: "empty-note"), .empty)
    }

    // MARK: - 3. Tab switch flushes editor

    func testTabSwitchCallsEditorFlushExactlyOnce() throws {
        var flushCount = 0
        let presenter = NoteTabsPresenter(editorFlush: { flushCount += 1 })
        let bridge = NoteTabsBridge(presenter: presenter)
        bridge.load(noteID: "flush-test")

        bridge.selectTab(.summary)
        XCTAssertEqual(flushCount, 1, "Switching from .privateNotes to .summary must flush exactly once")
    }

    func testSelectSameTabDoesNotFlush() throws {
        var flushCount = 0
        let presenter = NoteTabsPresenter(editorFlush: { flushCount += 1 })
        let bridge = NoteTabsBridge(presenter: presenter)
        bridge.load(noteID: "flush-test")

        bridge.selectTab(.summary)  // first switch: flushes
        flushCount = 0
        bridge.selectTab(.summary)  // same tab: no flush
        XCTAssertEqual(flushCount, 0)
    }

    func testMultipleTabSwitchesFlushEachTime() throws {
        var flushCount = 0
        let presenter = NoteTabsPresenter(editorFlush: { flushCount += 1 })
        let bridge = NoteTabsBridge(presenter: presenter)
        bridge.load(noteID: "flush-test")

        bridge.selectTab(.summary)
        bridge.selectTab(.transcript)
        bridge.selectTab(.privateNotes)
        XCTAssertEqual(flushCount, 3)
    }
}

// MARK: - Test doubles

private final class ControlledSummaryGenerator: SummaryGenerating, @unchecked Sendable {
    private let lock = NSLock()
    private var result: String?
    private var continuation: CheckedContinuation<String, Never>?

    func generate(for noteID: String) async throws -> String {
        await withCheckedContinuation { continuation in
            lock.lock()
            if let result {
                lock.unlock()
                continuation.resume(returning: result)
            } else {
                self.continuation = continuation
                lock.unlock()
            }
        }
    }

    func complete(with result: String) {
        lock.lock()
        self.result = result
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: result)
    }
}

private final class ImmediateSummaryGenerator: SummaryGenerating {
    let result: Result<String, Error>
    init(result: Result<String, Error>) { self.result = result }

    func generate(for noteID: String) async throws -> String {
        switch result {
        case .success(let s): return s
        case .failure(let e): throw e
        }
    }
}

private enum FakeError: Error, LocalizedError {
    case network
    var errorDescription: String? { "Fake network error" }
}
