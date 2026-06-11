import Foundation

// MARK: - Tab

public enum NoteTab: Equatable {
    case privateNotes
    case summary
    case transcript
}

// MARK: - Summary State

public enum SummaryState: Equatable {
    case needsTranscript    // no transcript yet — CTA is "Transcribe & summarize"
    case missing            // transcript exists but no summary — CTA is "Generate summary"
    case generating
    case ready(String)
    case failed(String)
}

// MARK: - Transcript State

public enum TranscriptState: Equatable {
    case empty
    case generating
    case segments([DisplaySegment])
}

// MARK: - Raw Segment (generic input — not Core types)

public struct RawSegment {
    public var speaker: String?
    public var timestamp: TimeInterval
    public var text: String
    public var source: TranscriptSource?

    public init(speaker: String?, timestamp: TimeInterval, text: String, source: TranscriptSource? = nil) {
        self.speaker = speaker
        self.timestamp = timestamp
        self.text = text
        self.source = source
    }
}

// MARK: - Display Segment

public struct DisplaySegment: Equatable {
    public var speaker: String?
    public var startStamp: String  // mm:ss
    public var text: String

    public init(speaker: String?, startStamp: String, text: String) {
        self.speaker = speaker
        self.startStamp = startStamp
        self.text = text
    }
}

// MARK: - SummaryGenerating

public protocol SummaryGenerating {
    func generate(for noteID: String) async throws -> String
}

// MARK: - TranscriptGenerating

public protocol TranscriptGenerating {
    func generate(for noteID: String) async throws -> [RawSegment]
}

// MARK: - NoteTabsPresenter

public final class NoteTabsPresenter {
    private var tabByNoteID: [String: NoteTab] = [:]
    private var summaryByNoteID: [String: SummaryState] = [:]
    private var transcriptByNoteID: [String: TranscriptState] = [:]
    private var speakerResolutionsByNoteID: [String: [String: SpeakerResolution]] = [:]

    private let summaryGenerator: (any SummaryGenerating)?
    private let transcriptGenerator: (any TranscriptGenerating)?
    private let editorFlush: () throws -> Void

    public var hasTranscriptGenerator: Bool { transcriptGenerator != nil }

    public var onPersistSummary: ((String, String) -> Void)?
    public var onPersistTranscript: ((String, [RawSegment]) -> Void)?
    public var onChange: (() -> Void)?

    public init(
        summaryGenerator: (any SummaryGenerating)? = nil,
        transcriptGenerator: (any TranscriptGenerating)? = nil,
        editorFlush: @escaping () throws -> Void = {}
    ) {
        self.summaryGenerator = summaryGenerator
        self.transcriptGenerator = transcriptGenerator
        self.editorFlush = editorFlush
    }

    // MARK: - Tab Selection

    public func selectedTab(for noteID: String) -> NoteTab {
        tabByNoteID[noteID] ?? .privateNotes
    }

    public func selectTab(_ tab: NoteTab, for noteID: String) throws {
        guard selectedTab(for: noteID) != tab else { return }
        try editorFlush()
        tabByNoteID[noteID] = tab
        onChange?()
    }

    // MARK: - Summary

    public func summaryState(for noteID: String) -> SummaryState {
        if let s = summaryByNoteID[noteID] { return s }
        // No summary yet — determine CTA based on whether a transcript exists
        switch transcriptByNoteID[noteID] {
        case .some(.segments(let segs)) where !segs.isEmpty:
            return .missing
        default:
            return .needsTranscript
        }
    }

    public func setSummary(_ text: String, for noteID: String) {
        summaryByNoteID[noteID] = .ready(text)
        onChange?()
    }

    public func generateSummary(for noteID: String) {
        guard let generator = summaryGenerator else { return }
        guard summaryByNoteID[noteID] != .generating else { return }
        summaryByNoteID[noteID] = .generating
        onChange?()

        Task { [weak self] in
            guard let self else { return }
            do {
                let summary = try await generator.generate(for: noteID)
                self.summaryByNoteID[noteID] = .ready(summary)
                self.onPersistSummary?(noteID, summary)
                self.onChange?()
            } catch {
                self.summaryByNoteID[noteID] = .failed(error.localizedDescription)
                self.onChange?()
            }
        }
    }

    // MARK: - Transcript

    public func transcriptState(for noteID: String) -> TranscriptState {
        transcriptByNoteID[noteID] ?? .empty
    }

    public func generateTranscript(for noteID: String) {
        guard let generator = transcriptGenerator else { return }
        guard transcriptByNoteID[noteID] != .generating else { return }
        transcriptByNoteID[noteID] = .generating
        onChange?()

        Task { [weak self] in
            guard let self else { return }
            do {
                let rawSegments = try await generator.generate(for: noteID)
                self.setSegments(rawSegments, for: noteID)
                self.onPersistTranscript?(noteID, rawSegments)
            } catch {
                self.transcriptByNoteID[noteID] = .empty
                self.onChange?()
            }
        }
    }

    public func transcribeAndSummarize(for noteID: String) {
        guard let generator = transcriptGenerator else { return }
        guard transcriptByNoteID[noteID] != .generating else { return }
        transcriptByNoteID[noteID] = .generating
        onChange?()

        Task { [weak self] in
            guard let self else { return }
            do {
                let rawSegments = try await generator.generate(for: noteID)
                self.setSegments(rawSegments, for: noteID)
                self.onPersistTranscript?(noteID, rawSegments)
                self.generateSummary(for: noteID)
            } catch {
                self.transcriptByNoteID[noteID] = .empty
                self.onChange?()
            }
        }
    }

    public func setSegments(_ rawSegments: [RawSegment], for noteID: String) {
        if rawSegments.isEmpty {
            transcriptByNoteID[noteID] = .empty
        } else {
            transcriptByNoteID[noteID] = .segments(Self.groupSegments(rawSegments))
        }
        onChange?()
    }

    /// Two-stream variant: merges mic and system-audio chronologically, infers speaker names.
    public func setSegments(
        mic: [RawSegment],
        systemAudio: [RawSegment],
        userName: String? = nil,
        participants: [Participant] = [],
        inPerson: Bool = false,
        for noteID: String
    ) {
        let merged = TranscriptMerger.merge(mic: mic, systemAudio: systemAudio, inPerson: inPerson)
        let micForNaming = mic
        let sysForNaming = inPerson ? [] : systemAudio
        let resolutions = TranscriptMerger.inferSpeakerNames(
            micSegments: micForNaming,
            systemAudioSegments: sysForNaming,
            userName: userName,
            participants: participants
        )
        speakerResolutionsByNoteID[noteID] = resolutions
        setSegments(merged, for: noteID)
    }

    public func speakerResolutions(for noteID: String) -> [String: SpeakerResolution] {
        speakerResolutionsByNoteID[noteID] ?? [:]
    }

    // MARK: - Segment Grouping

    public static func groupSegments(_ rawSegments: [RawSegment]) -> [DisplaySegment] {
        let sorted = rawSegments.sorted { $0.timestamp < $1.timestamp }
        var result: [DisplaySegment] = []
        for raw in sorted {
            if let last = result.last, last.speaker == raw.speaker {
                result[result.count - 1] = DisplaySegment(
                    speaker: last.speaker,
                    startStamp: last.startStamp,
                    text: last.text + " " + raw.text
                )
            } else {
                result.append(DisplaySegment(
                    speaker: raw.speaker,
                    startStamp: formatStamp(raw.timestamp),
                    text: raw.text
                ))
            }
        }
        return result
    }

    private static func formatStamp(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}
