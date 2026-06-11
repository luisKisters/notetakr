import XCTest
@testable import NoteTakrKit

final class RecordPillStateMachineTests: XCTestCase {

    // MARK: - Initial state

    func testInitialStateIsIdle() {
        let m = RecordPillStateMachine()
        XCTAssertEqual(m.state, .idle)
    }

    // MARK: - idle → recording

    func testTapFromIdleStartsRecordingAtZero() {
        let m = RecordPillStateMachine()
        m.tap()
        XCTAssertEqual(m.state, .recording(elapsed: 0))
    }

    func testTapFromIdleFiresOnStarted() {
        let m = RecordPillStateMachine()
        var fired = false
        m.onStarted = { fired = true }
        m.tap()
        XCTAssertTrue(fired)
    }

    func testTapFromIdleFiresOnStateChanged() {
        let m = RecordPillStateMachine()
        var received: RecordPillState?
        m.onStateChanged = { received = $0 }
        m.tap()
        XCTAssertEqual(received, .recording(elapsed: 0))
    }

    // MARK: - tick

    func testTickAdvancesElapsedWhenRecording() {
        let m = RecordPillStateMachine()
        m.tap()  // → recording(0)
        m.tick()
        XCTAssertEqual(m.state, .recording(elapsed: 1))
        m.tick()
        XCTAssertEqual(m.state, .recording(elapsed: 2))
    }

    func testTickIsNoOpWhenIdle() {
        let m = RecordPillStateMachine()
        m.tick()
        XCTAssertEqual(m.state, .idle)
    }

    func testTickIsNoOpWhenPaused() {
        let m = RecordPillStateMachine()
        m.tap()              // → recording(0)
        m.tick()             // → recording(1)
        m.menuPause()        // → paused(1)
        m.tick()             // no-op
        XCTAssertEqual(m.state, .paused(elapsed: 1))
    }

    func testTickIsNoOpWhenTranscribing() {
        let m = RecordPillStateMachine()
        m.tap()              // → recording(0)
        m.tap()              // fires onStopped (state unchanged by machine)
        m.beginTranscribing() // → transcribing
        m.tick()             // no-op
        XCTAssertEqual(m.state, .transcribing)
    }

    // MARK: - recording → pause (via caret menu)

    func testMenuPauseFromRecordingTransitionsToPaused() {
        let m = RecordPillStateMachine()
        m.tap()              // → recording(0)
        m.tick(); m.tick()   // → recording(2)
        m.menuPause()        // → paused(2)
        XCTAssertEqual(m.state, .paused(elapsed: 2))
    }

    func testMenuPauseIsNoOpWhenIdle() {
        let m = RecordPillStateMachine()
        m.menuPause()
        XCTAssertEqual(m.state, .idle)
    }

    func testMenuPauseIsNoOpWhenPaused() {
        let m = RecordPillStateMachine()
        m.tap(); m.menuPause()
        m.menuPause()        // already paused — no-op
        XCTAssertEqual(m.state, .paused(elapsed: 0))
    }

    // MARK: - paused → resume (main tap)

    func testTapFromPausedResumesRecording() {
        let m = RecordPillStateMachine()
        m.tap()              // → recording(0)
        m.tick(); m.tick(); m.tick()  // → recording(3)
        m.menuPause()        // → paused(3)
        m.tap()              // → recording(3) resume
        XCTAssertEqual(m.state, .recording(elapsed: 3))
    }

    func testTapFromPausedDoesNotFireOnStarted() {
        let m = RecordPillStateMachine()
        var count = 0
        m.onStarted = { count += 1 }
        m.tap()              // start → count=1
        m.menuPause()        // → paused
        m.tap()              // resume — NOT a new start
        XCTAssertEqual(count, 1)
    }

    func testElapsedPreservedAfterPauseResume() {
        let m = RecordPillStateMachine()
        m.tap()
        for _ in 0..<5 { m.tick() }  // → recording(5)
        m.menuPause()        // → paused(5)
        m.tap()              // resume → recording(5)
        XCTAssertEqual(m.state, .recording(elapsed: 5))
    }

    // MARK: - recording tap → onStopped(.summarize)

    func testTapFromRecordingFiresOnStoppedSummarize() {
        let m = RecordPillStateMachine()
        var receivedIntent: StopIntent?
        m.onStopped = { receivedIntent = $0 }
        m.tap()              // → recording
        m.tap()              // main tap while recording → onStopped(.summarize)
        XCTAssertEqual(receivedIntent, .summarize)
    }

    func testTapFromRecordingDoesNotChangeStateItself() {
        // The machine signals onStopped; controller drives state via beginTranscribing()
        let m = RecordPillStateMachine()
        m.tap()
        let preState = m.state
        m.tap()
        XCTAssertEqual(m.state, preState)  // still recording until controller calls beginTranscribing()
    }

    // MARK: - menuStopAndSummarize

    func testMenuStopAndSummarizeFromRecordingFiresSummarizeIntent() {
        let m = RecordPillStateMachine()
        var receivedIntent: StopIntent?
        m.onStopped = { receivedIntent = $0 }
        m.tap()              // → recording
        m.menuStopAndSummarize()
        XCTAssertEqual(receivedIntent, .summarize)
    }

    func testMenuStopAndSummarizeFromPausedFiresSummarizeIntent() {
        let m = RecordPillStateMachine()
        var receivedIntent: StopIntent?
        m.onStopped = { receivedIntent = $0 }
        m.tap(); m.menuPause()
        m.menuStopAndSummarize()
        XCTAssertEqual(receivedIntent, .summarize)
    }

    func testMenuStopAndSummarizeIsNoOpWhenIdle() {
        let m = RecordPillStateMachine()
        var fired = false
        m.onStopped = { _ in fired = true }
        m.menuStopAndSummarize()
        XCTAssertFalse(fired)
    }

    // MARK: - menuStopOnly → onStopped(.transcribe)

    func testMenuStopOnlyFromRecordingFiresTranscribeIntent() {
        let m = RecordPillStateMachine()
        var receivedIntent: StopIntent?
        m.onStopped = { receivedIntent = $0 }
        m.tap()
        m.menuStopOnly()
        XCTAssertEqual(receivedIntent, .transcribe)
    }

    func testMenuStopOnlyFromPausedFiresTranscribeIntent() {
        let m = RecordPillStateMachine()
        var receivedIntent: StopIntent?
        m.onStopped = { receivedIntent = $0 }
        m.tap(); m.menuPause()
        m.menuStopOnly()
        XCTAssertEqual(receivedIntent, .transcribe)
    }

    func testMenuStopOnlyIsNoOpWhenIdle() {
        let m = RecordPillStateMachine()
        var fired = false
        m.onStopped = { _ in fired = true }
        m.menuStopOnly()
        XCTAssertFalse(fired)
    }

    // MARK: - menuRestart

    func testMenuRestartFromRecordingResetsElapsedAndFiresOnStarted() {
        let m = RecordPillStateMachine()
        var count = 0
        m.onStarted = { count += 1 }
        m.tap()              // start (count=1)
        m.tick(); m.tick()   // → recording(2)
        m.menuRestart()      // → recording(0), count=2
        XCTAssertEqual(m.state, .recording(elapsed: 0))
        XCTAssertEqual(count, 2)
    }

    func testMenuRestartFromPausedResetsElapsedAndFiresOnStarted() {
        let m = RecordPillStateMachine()
        var count = 0
        m.onStarted = { count += 1 }
        m.tap(); m.tick(); m.tick(); m.tick()   // recording(3)
        m.menuPause()        // paused(3)
        m.menuRestart()      // → recording(0), count=2
        XCTAssertEqual(m.state, .recording(elapsed: 0))
        XCTAssertEqual(count, 2)
    }

    func testMenuRestartIsNoOpWhenIdle() {
        let m = RecordPillStateMachine()
        var fired = false
        m.onStarted = { fired = true }
        m.menuRestart()
        XCTAssertFalse(fired)
        XCTAssertEqual(m.state, .idle)
    }

    // MARK: - menuDiscard

    func testMenuDiscardFromRecordingGoesIdleFiresOnDiscarded() {
        let m = RecordPillStateMachine()
        var fired = false
        m.onDiscarded = { fired = true }
        m.tap()
        m.menuDiscard()
        XCTAssertEqual(m.state, .idle)
        XCTAssertTrue(fired)
    }

    func testMenuDiscardFromPausedGoesIdleFiresOnDiscarded() {
        let m = RecordPillStateMachine()
        var fired = false
        m.onDiscarded = { fired = true }
        m.tap(); m.menuPause()
        m.menuDiscard()
        XCTAssertEqual(m.state, .idle)
        XCTAssertTrue(fired)
    }

    func testMenuDiscardIsNoOpWhenIdle() {
        let m = RecordPillStateMachine()
        var fired = false
        m.onDiscarded = { fired = true }
        m.menuDiscard()
        XCTAssertFalse(fired)
        XCTAssertEqual(m.state, .idle)
    }

    // MARK: - Pipeline state pushes (beginTranscribing / beginSummarizing / finish*)

    func testAutoSummarizePipeline() {
        let m = RecordPillStateMachine()
        var stoppedIntent: StopIntent?
        m.onStopped = { stoppedIntent = $0 }

        m.tap()              // → recording(0)
        m.tick(); m.tick()   // → recording(2)
        m.tap()              // fires onStopped(.summarize)
        XCTAssertEqual(stoppedIntent, .summarize)

        // Controller drives the pipeline
        m.beginTranscribing()
        XCTAssertEqual(m.state, .transcribing)

        m.beginSummarizing()
        XCTAssertEqual(m.state, .summarizing)

        m.finishAsDone()
        XCTAssertEqual(m.state, .done)
    }

    func testStopOnlyPipeline() {
        let m = RecordPillStateMachine()
        var stoppedIntent: StopIntent?
        m.onStopped = { stoppedIntent = $0 }

        m.tap()              // → recording
        m.menuStopOnly()     // fires onStopped(.transcribe)
        XCTAssertEqual(stoppedIntent, .transcribe)

        m.beginTranscribing()
        XCTAssertEqual(m.state, .transcribing)

        m.finishAsDoneTranscript()
        XCTAssertEqual(m.state, .doneTranscript)
    }

    func testBeginSummarizingNoOpIfNotTranscribing() {
        let m = RecordPillStateMachine()
        m.tap()              // → recording
        m.beginSummarizing() // no-op: not in transcribing state
        XCTAssertEqual(m.state, .recording(elapsed: 0))
    }

    func testFinishAsDoneNoOpIfNotSummarizing() {
        let m = RecordPillStateMachine()
        m.finishAsDone()
        XCTAssertEqual(m.state, .idle)
    }

    func testFinishAsDoneTranscriptNoOpIfNotTranscribing() {
        let m = RecordPillStateMachine()
        m.finishAsDoneTranscript()
        XCTAssertEqual(m.state, .idle)
    }

    // MARK: - Tap on done states fires view callbacks

    func testTapDoneFiresOnViewSummary() {
        let m = RecordPillStateMachine()
        var summaryFired = false
        m.onViewSummary = { summaryFired = true }

        m.tap(); m.beginTranscribing(); m.beginSummarizing(); m.finishAsDone()
        XCTAssertEqual(m.state, .done)

        m.tap()
        XCTAssertTrue(summaryFired)
    }

    func testTapDoneTranscriptFiresOnViewTranscript() {
        let m = RecordPillStateMachine()
        var transcriptFired = false
        m.onViewTranscript = { transcriptFired = true }

        m.tap(); m.beginTranscribing(); m.finishAsDoneTranscript()
        XCTAssertEqual(m.state, .doneTranscript)

        m.tap()
        XCTAssertTrue(transcriptFired)
    }

    // MARK: - Busy states: tap is no-op

    func testTapTranscribingIsNoOp() {
        let m = RecordPillStateMachine()
        var stoppedCount = 0
        m.onStopped = { _ in stoppedCount += 1 }
        m.tap()              // start
        m.beginTranscribing()
        m.tap()              // no-op
        XCTAssertEqual(m.state, .transcribing)
        XCTAssertEqual(stoppedCount, 0)
    }

    func testTapSummarizingIsNoOp() {
        let m = RecordPillStateMachine()
        m.tap()
        m.beginTranscribing()
        m.beginSummarizing()
        m.tap()              // no-op
        XCTAssertEqual(m.state, .summarizing)
    }

    // MARK: - onStarted fires exactly once per new session

    func testOnStartedFiresExactlyOncePerNewSession() {
        let m = RecordPillStateMachine()
        var count = 0
        m.onStarted = { count += 1 }

        m.tap()              // new session: count=1
        m.menuPause()        // → paused (no new start)
        m.tap()              // resume (no new start)
        XCTAssertEqual(count, 1)
    }

    func testMenuRestartFiresOnStartedAgain() {
        let m = RecordPillStateMachine()
        var count = 0
        m.onStarted = { count += 1 }

        m.tap()              // count=1
        m.menuRestart()      // count=2
        XCTAssertEqual(count, 2)
    }

    // MARK: - onStopped does not fire on pause

    func testOnStoppedDoesNotFireOnMenuPause() {
        let m = RecordPillStateMachine()
        var fired = false
        m.onStopped = { _ in fired = true }

        m.tap()
        m.menuPause()
        XCTAssertFalse(fired)
    }

    // MARK: - Elapsed frozen while paused

    func testElapsedFrozenWhilePaused() {
        let m = RecordPillStateMachine()
        m.tap()
        m.tick(); m.tick(); m.tick()  // → recording(3)
        m.menuPause()        // → paused(3)
        m.tick(); m.tick(); m.tick()  // no-op
        XCTAssertEqual(m.state, .paused(elapsed: 3))
    }

    // MARK: - Full pipeline chain

    func testFullChainRecordPauseResumeStopSummarize() {
        let m = RecordPillStateMachine()
        var stateLog: [RecordPillState] = []
        m.onStateChanged = { stateLog.append($0) }

        m.tap()              // → recording(0)
        m.tick()             // → recording(1)
        m.menuPause()        // → paused(1)
        m.tap()              // → recording(1) resume
        m.tick()             // → recording(2)
        // Main tap while recording → onStopped(.summarize), state unchanged
        m.tap()
        m.beginTranscribing()
        m.beginSummarizing()
        m.finishAsDone()

        XCTAssertEqual(stateLog, [
            .recording(elapsed: 0),
            .recording(elapsed: 1),
            .paused(elapsed: 1),
            .recording(elapsed: 1),
            .recording(elapsed: 2),
            .transcribing,
            .summarizing,
            .done,
        ])
    }

    func testFullChainStopOnlyPath() {
        let m = RecordPillStateMachine()
        m.tap()
        m.tick(); m.tick()   // recording(2)
        m.menuStopOnly()
        m.beginTranscribing()
        m.finishAsDoneTranscript()
        XCTAssertEqual(m.state, .doneTranscript)
    }
}
