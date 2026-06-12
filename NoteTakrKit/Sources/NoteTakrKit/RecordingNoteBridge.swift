import Foundation

// MARK: - TranscriptionRequesting

public protocol TranscriptionRequesting {
    func transcribe(
        noteID: String,
        language: TranscribeLanguage,
        vocabulary: [String]
    ) async throws -> [RawSegment]
}

// MARK: - RecordingState

public enum RecordingState: Equatable {
    case idle
    case recording
    case transcribing
    case ready
    case failed(String)
}

// MARK: - RecordingNoteBridge

public final class RecordingNoteBridge {
    private let frontmatterPresenter: FrontmatterPresenter
    private let tabsPresenter: NoteTabsPresenter
    private let settings: EffectiveMeetingSettings
    private let transcriptionService: (any TranscriptionRequesting)?
    private let now: () -> Date

    public private(set) var state: RecordingState = .idle
    public var onChange: (() -> Void)?

    private var pendingNoteID: String?

    public init(
        frontmatterPresenter: FrontmatterPresenter,
        tabsPresenter: NoteTabsPresenter,
        settings: EffectiveMeetingSettings,
        transcriptionService: (any TranscriptionRequesting)? = nil,
        now: @escaping () -> Date = { Date() }
    ) {
        self.frontmatterPresenter = frontmatterPresenter
        self.tabsPresenter = tabsPresenter
        self.settings = settings
        self.transcriptionService = transcriptionService
        self.now = now
    }

    // MARK: - Lifecycle

    /// Marks the note live: sets the REC chip start timestamp on the frontmatter presenter.
    public func startRecording() {
        frontmatterPresenter.recordingStartedAt = now()
        state = .recording
        onChange?()
    }

    /// Clears the live state. When `settings.transcribe` is true and a service is injected,
    /// begins async transcription; otherwise transitions to idle immediately.
    public func stopRecording() {
        frontmatterPresenter.recordingStartedAt = nil

        guard settings.transcribe, let service = transcriptionService else {
            state = .idle
            onChange?()
            return
        }

        let noteID = frontmatterPresenter.note.id
        pendingNoteID = noteID
        beginTranscription(noteID: noteID, service: service)
    }

    /// Re-triggers transcription for the same note after a `.failed` state.
    public func retryTranscription() {
        guard case .failed = state,
              let noteID = pendingNoteID,
              let service = transcriptionService else { return }
        beginTranscription(noteID: noteID, service: service)
    }

    // MARK: - Private

    private func beginTranscription(noteID: String, service: any TranscriptionRequesting) {
        state = .transcribing
        onChange?()

        // Capture `self` STRONGLY for the duration of the async transcription.
        // The controller drops its reference to this bridge immediately after
        // calling stopRecording() (NotePanelController.recordingStopped sets
        // recordingBridge = nil). With a weak capture, ARC would deallocate the
        // bridge before this task runs, the `guard let self` would bail, and
        // transcription would silently never execute — leaving the record pill
        // stuck on "Transcribing…". The strong capture keeps the bridge alive
        // until the task finishes; it is released afterwards, so there is no leak.
        Task {
            do {
                let segments = try await service.transcribe(
                    noteID: noteID,
                    language: self.settings.language,
                    vocabulary: self.settings.vocabulary
                )
                self.tabsPresenter.setSegments(segments, for: noteID)
                self.state = .ready
                self.onChange?()
            } catch {
                self.state = .failed(error.localizedDescription)
                self.onChange?()
            }
        }
    }
}
