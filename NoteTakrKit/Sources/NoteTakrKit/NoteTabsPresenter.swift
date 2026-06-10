import Foundation

// MARK: - Tab

public enum NoteTab: Equatable {
    case privateNotes
    case summary
    case transcript
}

// MARK: - Summary State

public enum SummaryState: Equatable {
    case missing
    case generating
    case ready(String)
    case failed(String)
}

// MARK: - Transcript State

public enum TranscriptState: Equatable {
    case empty
    case segments([DisplaySegment])
}

// MARK: - Raw Segment (generic input — not Core types)

public struct RawSegment {
    public var speaker: String?
    public var timestamp: TimeInterval
    public var text: String

    public init(speaker: String?, timestamp: TimeInterval, text: String) {
        self.speaker = speaker
        self.timestamp = timestamp
        self.text = text
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

// MARK: - NoteTabsPresenter

public final class NoteTabsPresenter {
    private var tabByNoteID: [String: NoteTab] = [:]
    private var summaryByNoteID: [String: SummaryState] = [:]
    private var transcriptByNoteID: [String: TranscriptState] = [:]

    private let summaryGenerator: (any SummaryGenerating)?
    private let editorFlush: () throws -> Void

    public var onPersistSummary: ((String, String) -> Void)?
    public var onChange: (() -> Void)?

    public init(
        summaryGenerator: (any SummaryGenerating)? = nil,
        editorFlush: @escaping () throws -> Void = {}
    ) {
        self.summaryGenerator = summaryGenerator
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
        summaryByNoteID[noteID] ?? .missing
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

    public func setSegments(_ rawSegments: [RawSegment], for noteID: String) {
        if rawSegments.isEmpty {
            transcriptByNoteID[noteID] = .empty
        } else {
            transcriptByNoteID[noteID] = .segments(Self.groupSegments(rawSegments))
        }
        onChange?()
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
