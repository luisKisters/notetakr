import Foundation

// MARK: - RecordPillState

public enum RecordPillState: Equatable {
    case idle
    case recording(elapsed: Int)
    case paused(elapsed: Int)
    case transcribing
    case summarizing
    case done           // summarized (auto pipeline complete)
    case doneTranscript // stop-without-summarizing complete
}

// MARK: - StopIntent

public enum StopIntent: Equatable {
    case summarize      // stop → transcribe → summarize → done
    case transcribe     // stop → transcribe → doneTranscript
}

// MARK: - RecordPillStateMachine

/// Pure state machine for the record pill. Has no timer — callers invoke `tick()`
/// each second while in the `.recording` state. All callbacks fire synchronously
/// on the calling thread; the app layer is responsible for dispatch.
///
/// The SPLIT BADGE design (per recording-final.html):
///   • Main tap:  idle → start; recording → stop & summarize; paused → resume;
///                done/doneTranscript → view; transcribing/summarizing → no-op.
///   • Caret tap: (controlled by view) recording/paused only — shows per-state menu.
///   • Pipeline:  after onStopped fires, the controller drives state through
///                beginTranscribing → beginSummarizing → finishAsDone (or finishAsDoneTranscript).
public final class RecordPillStateMachine {

    public private(set) var state: RecordPillState = .idle

    // MARK: - Callbacks

    /// Fires on every state transition with the new state.
    public var onStateChanged: ((RecordPillState) -> Void)?

    /// Fires when entering recording from idle (new session start).
    public var onStarted: (() -> Void)?

    /// Fires when the user restarts mid-session (caret menu → Restart).
    /// Unlike onStarted, the controller must stop the current audio session before starting a new one.
    public var onRestarted: (() -> Void)?

    /// Fires when the user triggers a stop. Controller calls beginTranscribing() etc. afterwards.
    public var onStopped: ((StopIntent) -> Void)?

    /// Fires when the recording is discarded (no transcription).
    public var onDiscarded: (() -> Void)?

    /// Fires when the done-badge is tapped → open Summary tab.
    public var onViewSummary: (() -> Void)?

    /// Fires when the doneTranscript-badge is tapped → open Transcript tab.
    public var onViewTranscript: (() -> Void)?

    public init() {}

    // MARK: - View actions

    /// Main badge tap.
    ///   idle            → recording(0), fires onStarted
    ///   recording       → fires onStopped(.summarize) [controller drives the rest]
    ///   paused          → recording(elapsed) [resume]
    ///   transcribing    → no-op (busy)
    ///   summarizing     → no-op (busy)
    ///   done            → fires onViewSummary
    ///   doneTranscript  → fires onViewTranscript
    public func tap() {
        switch state {
        case .idle:
            transition(to: .recording(elapsed: 0))
            onStarted?()
        case .recording:
            onStopped?(.summarize)
        case .paused(let elapsed):
            transition(to: .recording(elapsed: elapsed))
        case .transcribing, .summarizing:
            break
        case .done:
            onViewSummary?()
        case .doneTranscript:
            onViewTranscript?()
        }
    }

    /// Advance the elapsed counter by one second. No-op unless `.recording`.
    public func tick() {
        guard case .recording(let elapsed) = state else { return }
        transition(to: .recording(elapsed: elapsed + 1))
    }

    // MARK: - Caret menu actions (recording / paused only)

    /// Caret menu: Pause — recording → paused.
    public func menuPause() {
        guard case .recording(let elapsed) = state else { return }
        transition(to: .paused(elapsed: elapsed))
    }

    /// Caret menu: Stop & summarize — fires onStopped(.summarize).
    public func menuStopAndSummarize() {
        guard isActiveRecording else { return }
        fireStop(.summarize)
    }

    /// Caret menu: Stop without summarizing — fires onStopped(.transcribe).
    public func menuStopOnly() {
        guard isActiveRecording else { return }
        fireStop(.transcribe)
    }

    /// Caret menu: Restart recording — back to recording(0), fires onRestarted.
    /// The controller must stop the in-flight audio session before starting a new one.
    public func menuRestart() {
        guard isActiveRecording else { return }
        transition(to: .recording(elapsed: 0))
        onRestarted?()
    }

    /// Caret menu: Discard — back to idle, fires onDiscarded.
    public func menuDiscard() {
        guard isActiveRecording else { return }
        transition(to: .idle)
        onDiscarded?()
    }

    // MARK: - Controller-driven pipeline state pushes

    /// Called by controller after audio stops and transcription begins.
    public func beginTranscribing() {
        transition(to: .transcribing)
    }

    /// Called by controller when transcription finishes and summarization begins.
    public func beginSummarizing() {
        guard state == .transcribing else { return }
        transition(to: .summarizing)
    }

    /// Called by controller when the full summarize pipeline completes.
    public func finishAsDone() {
        guard state == .summarizing else { return }
        transition(to: .done)
    }

    /// Called by controller when transcription-only pipeline completes.
    public func finishAsDoneTranscript() {
        guard state == .transcribing else { return }
        transition(to: .doneTranscript)
    }

    // MARK: - Private

    private var isActiveRecording: Bool {
        if case .recording = state { return true }
        if case .paused = state { return true }
        return false
    }

    private func fireStop(_ intent: StopIntent) {
        guard isActiveRecording else { return }
        onStopped?(intent)
    }

    private func transition(to newState: RecordPillState) {
        state = newState
        onStateChanged?(newState)
    }
}
