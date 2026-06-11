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
        m.tap()              // → paused(1)
        m.tick()             // no-op
        XCTAssertEqual(m.state, .paused(elapsed: 1))
    }

    func testTickIsNoOpWhenShowingMenu() {
        let m = RecordPillStateMachine()
        m.tap()              // → recording(0)
        m.tap()              // → paused(0)
        m.tap()              // → showingMenu(0)
        m.tick()             // no-op
        XCTAssertEqual(m.state, .showingMenu(elapsed: 0))
    }

    // MARK: - recording → paused

    func testTapFromRecordingTransitionsToPaused() {
        let m = RecordPillStateMachine()
        m.tap()              // → recording(0)
        m.tick()             // → recording(1)
        m.tick()             // → recording(2)
        m.tap()              // → paused(2)
        XCTAssertEqual(m.state, .paused(elapsed: 2))
    }

    func testPausedPreservesElapsedFromRecording() {
        let m = RecordPillStateMachine()
        m.tap()
        for _ in 0..<5 { m.tick() }
        m.tap()
        XCTAssertEqual(m.state, .paused(elapsed: 5))
    }

    // MARK: - paused → showingMenu

    func testTapFromPausedOpensMenu() {
        let m = RecordPillStateMachine()
        m.tap()
        m.tap()
        m.tap()
        XCTAssertEqual(m.state, .showingMenu(elapsed: 0))
    }

    // MARK: - showingMenu → paused (dismiss)

    func testTapFromShowingMenuDismissesMenuToPaused() {
        let m = RecordPillStateMachine()
        m.tap()
        m.tap()              // → paused
        m.tick()             // no-op
        m.tap()              // → showingMenu(0)
        m.tap()              // → paused(0) — dismiss
        XCTAssertEqual(m.state, .paused(elapsed: 0))
    }

    // MARK: - menuResume

    func testMenuResumeFromShowingMenuReturnsToRecordingAtSameElapsed() {
        let m = RecordPillStateMachine()
        m.tap()              // → recording(0)
        m.tick(); m.tick(); m.tick()  // → recording(3)
        m.tap()              // → paused(3)
        m.tap()              // → showingMenu(3)
        m.menuResume()       // → recording(3)
        XCTAssertEqual(m.state, .recording(elapsed: 3))
    }

    func testMenuResumeIsNoOpWhenNotShowingMenu() {
        let m = RecordPillStateMachine()
        m.menuResume()       // idle → no-op
        XCTAssertEqual(m.state, .idle)

        m.tap()              // → recording(0)
        m.menuResume()       // still recording → no-op
        XCTAssertEqual(m.state, .recording(elapsed: 0))
    }

    func testAfterResumeTimerContinuesToTick() {
        let m = RecordPillStateMachine()
        m.tap()
        m.tick(); m.tick()   // → recording(2)
        m.tap()              // → paused(2)
        m.tap()              // → showingMenu(2)
        m.menuResume()       // → recording(2)
        m.tick()             // → recording(3)
        XCTAssertEqual(m.state, .recording(elapsed: 3))
    }

    // MARK: - menuStopAndTranscribe

    func testStopAndTranscribeGoesIdleWithTranscribeIntent() {
        let m = RecordPillStateMachine()
        var receivedIntent: StopIntent?
        m.onStopped = { receivedIntent = $0 }

        m.tap()              // → recording(0)
        m.tick(); m.tick()   // → recording(2)
        m.tap()              // → paused(2)
        m.tap()              // → showingMenu(2)
        m.menuStopAndTranscribe()

        XCTAssertEqual(m.state, .idle)
        XCTAssertEqual(receivedIntent, .transcribe)
    }

    func testStopAndTranscribeIsNoOpWhenNotShowingMenu() {
        let m = RecordPillStateMachine()
        var fired = false
        m.onStopped = { _ in fired = true }

        m.tap()              // → recording(0)
        m.menuStopAndTranscribe()  // no-op
        XCTAssertFalse(fired)
        XCTAssertEqual(m.state, .recording(elapsed: 0))
    }

    // MARK: - menuStopAndSummarize

    func testStopAndSummarizeGoesIdleWithSummarizeIntent() {
        let m = RecordPillStateMachine()
        var receivedIntent: StopIntent?
        m.onStopped = { receivedIntent = $0 }

        m.tap()
        m.tap()              // → paused(0)
        m.tap()              // → showingMenu(0)
        m.menuStopAndSummarize()

        XCTAssertEqual(m.state, .idle)
        XCTAssertEqual(receivedIntent, .summarize)
    }

    func testStopAndSummarizeSignalsSummarizeNotTranscribe() {
        let m = RecordPillStateMachine()
        var intents: [StopIntent] = []
        m.onStopped = { intents.append($0) }

        m.tap(); m.tap(); m.tap()
        m.menuStopAndSummarize()

        XCTAssertEqual(intents, [.summarize])
    }

    func testStopAndSummarizeIsNoOpWhenNotShowingMenu() {
        let m = RecordPillStateMachine()
        var fired = false
        m.onStopped = { _ in fired = true }

        m.tap(); m.tap()     // → paused(0)
        m.menuStopAndSummarize()  // no-op
        XCTAssertFalse(fired)
        XCTAssertEqual(m.state, .paused(elapsed: 0))
    }

    // MARK: - Full chain: idle → rec → paused → resume → rec → stop

    func testFullChainIdleToRecordingToPausedToResumedToStop() {
        let m = RecordPillStateMachine()
        var stateLog: [RecordPillState] = []
        m.onStateChanged = { stateLog.append($0) }

        m.tap()              // → recording(0)
        m.tick()             // → recording(1)
        m.tap()              // → paused(1)
        m.tap()              // → showingMenu(1)
        m.menuResume()       // → recording(1)
        m.tick()             // → recording(2)
        m.tap()              // → paused(2)
        m.tap()              // → showingMenu(2)
        m.menuStopAndTranscribe()  // → idle

        XCTAssertEqual(stateLog, [
            .recording(elapsed: 0),
            .recording(elapsed: 1),
            .paused(elapsed: 1),
            .showingMenu(elapsed: 1),
            .recording(elapsed: 1),
            .recording(elapsed: 2),
            .paused(elapsed: 2),
            .showingMenu(elapsed: 2),
            .idle,
        ])
    }

    // MARK: - onStarted fires exactly once per start

    func testOnStartedFiresExactlyOncePerStart() {
        let m = RecordPillStateMachine()
        var count = 0
        m.onStarted = { count += 1 }

        m.tap()              // start
        m.tap()              // → paused (no new start)
        m.tap()              // → showingMenu (no new start)
        m.menuResume()       // → recording again (resume, not a new "start")
        // Note: menuResume does NOT fire onStarted — it's a resume, not a new session
        XCTAssertEqual(count, 1)
    }

    // MARK: - onStopped does not fire on pause or menu open

    func testOnStoppedDoesNotFireOnPauseOrMenuOpen() {
        let m = RecordPillStateMachine()
        var fired = false
        m.onStopped = { _ in fired = true }

        m.tap()   // → recording
        m.tap()   // → paused
        m.tap()   // → showingMenu
        XCTAssertFalse(fired)
    }

    // MARK: - Timer pause/resume semantics (elapsed frozen while paused)

    func testElapsedFrozenWhilePaused() {
        let m = RecordPillStateMachine()
        m.tap()              // → recording(0)
        m.tick(); m.tick(); m.tick()  // → recording(3)
        m.tap()              // → paused(3)
        // These ticks must not advance elapsed
        m.tick(); m.tick(); m.tick()
        m.tap()              // → showingMenu(3)
        XCTAssertEqual(m.state, .showingMenu(elapsed: 3))
    }
}
