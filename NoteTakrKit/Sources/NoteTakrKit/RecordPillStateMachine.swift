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
    public private(set) var isStartPending = false

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

    public static func displayState(
        actualState: RecordPillState,
        currentNoteID: String,
        activeRecordingNoteID: String?
    ) -> RecordPillState {
        guard let activeRecordingNoteID,
              !currentNoteID.isEmpty,
              activeRecordingNoteID != currentNoteID else {
            return actualState
        }

        switch actualState {
        case .recording, .paused:
            return .idle
        default:
            return actualState
        }
    }

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
            transition(to: .transcribing)
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

    /// App-facing start request. Unlike `tap()` this does not optimistically enter
    /// `.recording`; the controller must call `confirmStarted()` after the recorder
    /// actually starts.
    public func requestStart() {
        guard state == .idle, !isStartPending, let onStarted else { return }
        isStartPending = true
        onStarted()
    }

    /// Confirms a pending start after the backing recorder is live.
    public func confirmStarted() {
        guard isStartPending, state == .idle else { return }
        isStartPending = false
        transition(to: .recording(elapsed: 0))
    }

    /// Mirrors a recording that was started outside the pill, such as a menu-bar
    /// command or global shortcut. This keeps the pill honest without firing
    /// `onStarted` and accidentally starting a second backing recorder.
    public func reflectExternalRecordingStarted(elapsed: Int = 0) {
        isStartPending = false
        switch state {
        case .idle, .done, .doneTranscript:
            transition(to: .recording(elapsed: max(0, elapsed)))
        case .recording, .paused, .transcribing, .summarizing:
            break
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
        guard isActiveRecording else { return }
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

    /// Resets to idle if the machine is mid-pipeline (transcribing or summarizing).
    /// Call when the pipeline is cancelled (e.g., user switches notes).
    public func cancelBusyPipeline() {
        if state == .transcribing || state == .summarizing {
            transition(to: .idle)
        }
    }

    /// Unconditionally resets the machine to `.idle`.
    ///
    /// The pill is a single global machine shared across notes, so terminal states
    /// (`.done`/`.doneTranscript`) would otherwise leak onto a freshly opened note and
    /// make it look already "Transcribed". Call this when loading any note so every note
    /// opens at Record. Unlike `cancelBusyPipeline()`, this resets from terminal states too.
    public func reset() {
        isStartPending = false
        if state != .idle {
            transition(to: .idle)
        }
    }

    // MARK: - Private

    private var isActiveRecording: Bool {
        if case .recording = state { return true }
        if case .paused = state { return true }
        return false
    }

    private func fireStop(_ intent: StopIntent) {
        guard isActiveRecording else { return }
        transition(to: .transcribing)
        onStopped?(intent)
    }

    private func transition(to newState: RecordPillState) {
        state = newState
        onStateChanged?(newState)
    }
}
