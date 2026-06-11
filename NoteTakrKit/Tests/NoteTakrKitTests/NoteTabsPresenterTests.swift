import XCTest
@testable import NoteTakrKit

final class NoteTabsPresenterTests: XCTestCase {

    // MARK: - Default state

    func testDefaultTabIsPrivateNotes() {
        let p = NoteTabsPresenter()
        XCTAssertEqual(p.selectedTab(for: "n1"), .privateNotes)
    }

    func testDefaultSummaryIsMissing() {
        let p = NoteTabsPresenter()
        XCTAssertEqual(p.summaryState(for: "n1"), .missing)
    }

    func testDefaultTranscriptIsEmpty() {
        let p = NoteTabsPresenter()
        XCTAssertEqual(p.transcriptState(for: "n1"), .empty)
    }

    // MARK: - Tab switching

    func testSelectTabChangesState() throws {
        let p = NoteTabsPresenter()
        try p.selectTab(.summary, for: "n1")
        XCTAssertEqual(p.selectedTab(for: "n1"), .summary)
    }

    func testSelectSameTabDoesNotFlush() throws {
        var flushCount = 0
        let p = NoteTabsPresenter(editorFlush: { flushCount += 1 })
        try p.selectTab(.summary, for: "n1")   // changes from default, flushes
        flushCount = 0
        try p.selectTab(.summary, for: "n1")   // same tab — no flush
        XCTAssertEqual(flushCount, 0, "Selecting same tab must not call flush")
    }

    func testTabSelectionPersistedPerNoteID() throws {
        let p = NoteTabsPresenter()
        try p.selectTab(.transcript, for: "n1")
        try p.selectTab(.summary, for: "n2")
        XCTAssertEqual(p.selectedTab(for: "n1"), .transcript)
        XCTAssertEqual(p.selectedTab(for: "n2"), .summary)
    }

    func testTabSwitchFiresOnChange() throws {
        var count = 0
        let p = NoteTabsPresenter()
        p.onChange = { count += 1 }
        try p.selectTab(.summary, for: "n1")
        XCTAssertEqual(count, 1)
    }

    // MARK: - Flush on tab switch

    func testSwitchingTabCallsEditorFlushExactlyOnce() throws {
        var flushCount = 0
        let p = NoteTabsPresenter(editorFlush: { flushCount += 1 })
        try p.selectTab(.summary, for: "n1")
        XCTAssertEqual(flushCount, 1)
    }

    func testSelectDefaultTabFromDefaultDoesNotFlush() throws {
        var flushCount = 0
        let p = NoteTabsPresenter(editorFlush: { flushCount += 1 })
        try p.selectTab(.privateNotes, for: "n1")  // already .privateNotes by default
        XCTAssertEqual(flushCount, 0)
    }

    func testMultipleTabSwitchesFlushEachTime() throws {
        var flushCount = 0
        let p = NoteTabsPresenter(editorFlush: { flushCount += 1 })
        try p.selectTab(.summary, for: "n1")     // flush 1
        try p.selectTab(.transcript, for: "n1") // flush 2
        try p.selectTab(.privateNotes, for: "n1") // flush 3
        XCTAssertEqual(flushCount, 3)
    }

    // MARK: - Summary: setSummary

    func testSetSummaryMakesReady() {
        let p = NoteTabsPresenter()
        p.setSummary("The summary text", for: "n1")
        XCTAssertEqual(p.summaryState(for: "n1"), .ready("The summary text"))
    }

    func testSetSummaryFiresOnChange() {
        var count = 0
        let p = NoteTabsPresenter()
        p.onChange = { count += 1 }
        p.setSummary("text", for: "n1")
        XCTAssertEqual(count, 1)
    }

    // MARK: - Summary: generation happy path

    func testGenerateSummaryHappyPath() {
        let readyExp = expectation(description: "summary ready")
        let generator = ImmediateMockGenerator(result: .success("AI summary"))
        let p = NoteTabsPresenter(summaryGenerator: generator)
        var sawGenerating = false

        p.onChange = {
            switch p.summaryState(for: "n1") {
            case .generating: sawGenerating = true
            case .ready: readyExp.fulfill()
            default: break
            }
        }

        p.generateSummary(for: "n1")
        XCTAssertEqual(p.summaryState(for: "n1"), .generating, "Must transition to generating synchronously")

        waitForExpectations(timeout: 2)
        XCTAssertTrue(sawGenerating, "generating state must have been observed before ready")
        XCTAssertEqual(p.summaryState(for: "n1"), .ready("AI summary"))
    }

    func testGenerateSummaryCallsOnPersist() {
        let persistExp = expectation(description: "persist called")
        let generator = ImmediateMockGenerator(result: .success("summary text"))
        let p = NoteTabsPresenter(summaryGenerator: generator)
        p.onPersistSummary = { noteID, text in
            XCTAssertEqual(noteID, "n1")
            XCTAssertEqual(text, "summary text")
            persistExp.fulfill()
        }
        p.generateSummary(for: "n1")
        waitForExpectations(timeout: 2)
    }

    // MARK: - Summary: generation failure

    func testGenerateSummaryFailure() {
        let failedExp = expectation(description: "summary failed")
        let generator = ImmediateMockGenerator(result: .failure(TestGeneratorError.network("network error")))
        let p = NoteTabsPresenter(summaryGenerator: generator)

        p.onChange = {
            if case .failed = p.summaryState(for: "n1") { failedExp.fulfill() }
        }
        p.generateSummary(for: "n1")
        waitForExpectations(timeout: 2)

        if case .failed(let msg) = p.summaryState(for: "n1") {
            XCTAssertFalse(msg.isEmpty, "Failure message must be non-empty")
        } else {
            XCTFail("Expected .failed state, got \(p.summaryState(for: "n1"))")
        }
    }

    func testRetryAfterFailureSucceeds() {
        let failedExp = expectation(description: "first attempt failed")
        let readyExp = expectation(description: "retry succeeded")
        var failedOnce = false

        let generator = SequentialMockGenerator(results: [
            .failure(TestGeneratorError.network("first error")),
            .success("retried summary")
        ])
        let p = NoteTabsPresenter(summaryGenerator: generator)

        p.onChange = {
            switch p.summaryState(for: "n1") {
            case .failed:
                if !failedOnce {
                    failedOnce = true
                    failedExp.fulfill()
                    // State is .failed (not .generating), so retry is allowed
                    p.generateSummary(for: "n1")
                }
            case .ready:
                readyExp.fulfill()
            default:
                break
            }
        }

        p.generateSummary(for: "n1")
        wait(for: [failedExp, readyExp], timeout: 4, enforceOrder: true)
        XCTAssertEqual(p.summaryState(for: "n1"), .ready("retried summary"))
    }

    // MARK: - Summary: guard against double-generate

    func testGenerateWhileGeneratingIsNoop() {
        // Use a suspending generator so we can guarantee the second call happens
        // while the first Task is blocked — eliminating the race on Linux.
        let canProceed = DispatchSemaphore(value: 0)
        let started = DispatchSemaphore(value: 0)
        let readyExp = expectation(description: "generation done")
        var generateCallCount = 0

        let generator = SuspendingCallCountingGenerator(
            onGenerate: { generateCallCount += 1; return "result" },
            started: started,
            canProceed: canProceed
        )
        let p = NoteTabsPresenter(summaryGenerator: generator)
        p.onChange = {
            if case .ready = p.summaryState(for: "n1") { readyExp.fulfill() }
        }

        p.generateSummary(for: "n1")        // starts generation, state = .generating
        started.wait()                      // wait until Task is suspended inside generator
        p.generateSummary(for: "n1")       // must be ignored by guard — state IS .generating
        canProceed.signal()                 // let generator finish

        waitForExpectations(timeout: 2)
        XCTAssertEqual(generateCallCount, 1, "Second call while generating must not invoke generate")
    }

    func testNoGeneratorLeavesStateMissing() {
        let p = NoteTabsPresenter(summaryGenerator: nil)
        p.generateSummary(for: "n1")
        XCTAssertEqual(p.summaryState(for: "n1"), .missing)
    }

    // MARK: - Transcript: empty and segments

    func testSetEmptySegmentsProducesEmpty() {
        let p = NoteTabsPresenter()
        p.setSegments([], for: "n1")
        XCTAssertEqual(p.transcriptState(for: "n1"), .empty)
    }

    func testSetSegmentsFiresOnChange() {
        var count = 0
        let p = NoteTabsPresenter()
        p.onChange = { count += 1 }
        p.setSegments([RawSegment(speaker: "A", timestamp: 0, text: "Hi")], for: "n1")
        XCTAssertEqual(count, 1)
    }

    func testSetSegmentsPerNoteID() {
        let p = NoteTabsPresenter()
        p.setSegments([RawSegment(speaker: "A", timestamp: 0, text: "Hello")], for: "n1")
        p.setSegments([], for: "n2")
        XCTAssertNotEqual(p.transcriptState(for: "n1"), .empty)
        XCTAssertEqual(p.transcriptState(for: "n2"), .empty)
    }

    // MARK: - Segment grouping: speaker changes

    func testGroupSegments_differentSpeakers() {
        let raw = [
            RawSegment(speaker: "Alice", timestamp: 0, text: "Hello"),
            RawSegment(speaker: "Bob", timestamp: 5, text: "World")
        ]
        let result = NoteTabsPresenter.groupSegments(raw)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0], DisplaySegment(speaker: "Alice", startStamp: "0:00", text: "Hello"))
        XCTAssertEqual(result[1], DisplaySegment(speaker: "Bob", startStamp: "0:05", text: "World"))
    }

    func testGroupSegments_sameSpeakerConsecutiveMerges() {
        let raw = [
            RawSegment(speaker: "Alice", timestamp: 0, text: "First"),
            RawSegment(speaker: "Alice", timestamp: 3, text: "Second")
        ]
        let result = NoteTabsPresenter.groupSegments(raw)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0], DisplaySegment(speaker: "Alice", startStamp: "0:00", text: "First Second"))
    }

    func testGroupSegments_sameSpeakerNotConsecutive_notMerged() {
        let raw = [
            RawSegment(speaker: "Alice", timestamp: 0, text: "A1"),
            RawSegment(speaker: "Bob", timestamp: 2, text: "B1"),
            RawSegment(speaker: "Alice", timestamp: 5, text: "A2")
        ]
        let result = NoteTabsPresenter.groupSegments(raw)
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result[0].text, "A1")
        XCTAssertEqual(result[1].text, "B1")
        XCTAssertEqual(result[2].text, "A2")
    }

    // MARK: - Segment grouping: nil speakers

    func testGroupSegments_nilSpeakers_consecutiveMerged() {
        let raw = [
            RawSegment(speaker: nil, timestamp: 0, text: "First"),
            RawSegment(speaker: nil, timestamp: 1, text: "Second")
        ]
        let result = NoteTabsPresenter.groupSegments(raw)
        XCTAssertEqual(result.count, 1)
        XCTAssertNil(result[0].speaker)
        XCTAssertEqual(result[0].text, "First Second")
    }

    func testGroupSegments_nilAndNamedSpeaker_notMerged() {
        let raw = [
            RawSegment(speaker: nil, timestamp: 0, text: "Anonymous"),
            RawSegment(speaker: "Alice", timestamp: 1, text: "Named")
        ]
        let result = NoteTabsPresenter.groupSegments(raw)
        XCTAssertEqual(result.count, 2)
        XCTAssertNil(result[0].speaker)
        XCTAssertEqual(result[1].speaker, "Alice")
    }

    // MARK: - Segment grouping: out-of-order timestamps sorted

    func testGroupSegments_sortedByTimestamp() {
        let raw = [
            RawSegment(speaker: "Bob", timestamp: 10, text: "Later"),
            RawSegment(speaker: "Alice", timestamp: 0, text: "Earlier")
        ]
        let result = NoteTabsPresenter.groupSegments(raw)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].speaker, "Alice")
        XCTAssertEqual(result[0].startStamp, "0:00")
        XCTAssertEqual(result[1].speaker, "Bob")
        XCTAssertEqual(result[1].startStamp, "0:10")
    }

    // MARK: - Segment grouping: mm:ss stamp format

    func testGroupSegments_stampZero() {
        let raw = [RawSegment(speaker: "A", timestamp: 0, text: "hi")]
        XCTAssertEqual(NoteTabsPresenter.groupSegments(raw)[0].startStamp, "0:00")
    }

    func testGroupSegments_stamp90Seconds() {
        let raw = [RawSegment(speaker: "A", timestamp: 90, text: "hi")]
        XCTAssertEqual(NoteTabsPresenter.groupSegments(raw)[0].startStamp, "1:30")
    }

    func testGroupSegments_stampLargeMinutes() {
        let raw = [RawSegment(speaker: "A", timestamp: 3900, text: "hi")]
        XCTAssertEqual(NoteTabsPresenter.groupSegments(raw)[0].startStamp, "65:00")
    }

    // MARK: - State matrix

    func testNoteWithTranscriptSegments() {
        let p = NoteTabsPresenter()
        p.setSegments([RawSegment(speaker: "Alice", timestamp: 0, text: "Hello world")], for: "n1")
        if case .segments(let segs) = p.transcriptState(for: "n1") {
            XCTAssertEqual(segs.count, 1)
            XCTAssertEqual(segs[0].text, "Hello world")
        } else {
            XCTFail("Expected .segments state")
        }
    }

    func testNoteWithoutTranscriptIsEmpty() {
        XCTAssertEqual(NoteTabsPresenter().transcriptState(for: "nonexistent"), .empty)
    }

    func testNoteWithSummaryAlreadySet() {
        let p = NoteTabsPresenter()
        p.setSummary("Existing summary", for: "n1")
        XCTAssertEqual(p.summaryState(for: "n1"), .ready("Existing summary"))
    }

    func testNoteWithoutSummaryIsMissing() {
        XCTAssertEqual(NoteTabsPresenter().summaryState(for: "nonexistent"), .missing)
    }
}

// MARK: - Test doubles

private final class ImmediateMockGenerator: SummaryGenerating {
    let result: Result<String, Error>
    init(result: Result<String, Error>) { self.result = result }

    func generate(for noteID: String) async throws -> String {
        // Yield so the caller can observe the intermediate .generating state
        // before this task completes (Swift 6 schedules tasks eagerly).
        await Task.yield()
        switch result {
        case .success(let s): return s
        case .failure(let e): throw e
        }
    }
}

private final class SequentialMockGenerator: SummaryGenerating {
    private let results: [Result<String, Error>]
    private var index = 0

    init(results: [Result<String, Error>]) {
        self.results = results
    }

    func generate(for noteID: String) async throws -> String {
        let r = results[min(index, results.count - 1)]
        index += 1
        switch r {
        case .success(let s): return s
        case .failure(let e): throw e
        }
    }
}

private final class CallCountingGenerator: SummaryGenerating {
    private let onGenerate: () -> String

    init(onGenerate: @escaping () -> String) {
        self.onGenerate = onGenerate
    }

    func generate(for noteID: String) async throws -> String {
        return onGenerate()
    }
}

// Suspends until canProceed is signaled — guarantees the caller sees .generating state
// before the generator returns, eliminating the Linux race in testGenerateWhileGeneratingIsNoop.
private final class SuspendingCallCountingGenerator: SummaryGenerating, @unchecked Sendable {
    private let onGenerate: () -> String
    private let started: DispatchSemaphore
    private let canProceed: DispatchSemaphore

    init(onGenerate: @escaping () -> String,
         started: DispatchSemaphore,
         canProceed: DispatchSemaphore) {
        self.onGenerate = onGenerate
        self.started = started
        self.canProceed = canProceed
    }

    func generate(for noteID: String) async throws -> String {
        return await withCheckedContinuation { cont in
            DispatchQueue.global().async {
                self.started.signal()       // tell test we're running
                self.canProceed.wait()      // block until test proceeds
                cont.resume(returning: self.onGenerate())
            }
        }
    }
}

private enum TestGeneratorError: Error, LocalizedError {
    case network(String)

    var errorDescription: String? {
        if case .network(let msg) = self { return msg }
        return nil
    }
}
