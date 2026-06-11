import Foundation

// MARK: - RecordPillState

public enum RecordPillState: Equatable {
    case idle
    case recording(elapsed: Int)
    case paused(elapsed: Int)
    case showingMenu(elapsed: Int)
}

// MARK: - StopIntent

public enum StopIntent: Equatable {
    case transcribe
    case summarize
}

// MARK: - RecordPillStateMachine

/// Pure state machine for the record pill. Has no timer — callers invoke `tick()`
/// each second while the machine is in the `.recording` state. All callbacks fire
/// synchronously on the calling thread; the app layer is responsible for dispatch.
public final class RecordPillStateMachine {

    public private(set) var state: RecordPillState = .idle

    /// Fires on every state transition with the new state.
    public var onStateChanged: ((RecordPillState) -> Void)?

    /// Fires when the machine leaves `.idle` and enters `.recording`.
    /// Use this to start actual audio recording.
    public var onStarted: (() -> Void)?

    /// Fires when the machine returns to `.idle` via a Stop menu action.
    /// The intent tells the caller whether to transcribe or switch to Summary + summarize.
    public var onStopped: ((StopIntent) -> Void)?

    public init() {}

    // MARK: - Actions

    /// Tap on the pill body (not inside the open menu).
    /// Transitions: idle → recording(0); recording → paused; paused → showingMenu; showingMenu → paused (dismisses).
    public func tap() {
        switch state {
        case .idle:
            transition(to: .recording(elapsed: 0))
            onStarted?()
        case .recording(let elapsed):
            transition(to: .paused(elapsed: elapsed))
        case .paused(let elapsed):
            transition(to: .showingMenu(elapsed: elapsed))
        case .showingMenu(let elapsed):
            transition(to: .paused(elapsed: elapsed))
        }
    }

    /// Advance the elapsed counter by one second. No-op unless currently `.recording`.
    public func tick() {
        guard case .recording(let elapsed) = state else { return }
        transition(to: .recording(elapsed: elapsed + 1))
    }

    /// Menu "Resume" — returns from showingMenu back to recording, keeping elapsed intact.
    public func menuResume() {
        guard case .showingMenu(let elapsed) = state else { return }
        transition(to: .recording(elapsed: elapsed))
    }

    /// Menu "Stop & Transcribe" — returns to idle and signals the transcribe intent.
    public func menuStopAndTranscribe() {
        guard case .showingMenu = state else { return }
        transition(to: .idle)
        onStopped?(.transcribe)
    }

    /// Menu "Stop & Summarize" — returns to idle and signals the summarize intent,
    /// which the caller should use to switch to the Summary tab and start generation.
    public func menuStopAndSummarize() {
        guard case .showingMenu = state else { return }
        transition(to: .idle)
        onStopped?(.summarize)
    }

    // MARK: - Private

    private func transition(to newState: RecordPillState) {
        state = newState
        onStateChanged?(newState)
    }
}
