import Foundation

/// Pure logic for combining several independently-transcribed audio streams
/// (e.g. the microphone and the system-audio capture) into one timeline-ordered,
/// speaker-labelled transcript. Kept free of FluidAudio and any I/O so it can be
/// unit-tested deterministically, mirroring the style of `TranscriptAssembler`.
public enum TranscriptMerger {

    /// Label applied to the local microphone stream — the person running the app.
    public static let primarySpeakerLabel = "Speaker 1 (You)"

    /// Relabels every segment to a single speaker. Used for the microphone stream,
    /// which is assumed to hold one voice (the user) and therefore needs no
    /// diarization.
    public static func forceSingleSpeaker(_ segments: [TranscriptSegment], label: String) -> [TranscriptSegment] {
        segments.map { segment in
            var copy = segment
            copy.speaker = label
            return copy
        }
    }

    /// Shifts diarized "Speaker N" labels so they start at `start` instead of 1,
    /// keeping distinct speakers distinct. Used for the system-audio stream so its
    /// speakers slot in after the microphone's "Speaker 1 (You)".
    ///
    /// A segment with no speaker (diarization unavailable → a single merged
    /// segment) is labelled "Speaker {start}" so it is still distinguished from
    /// the microphone. Non-"Speaker N" labels are left untouched.
    public static func offsetSpeakers(_ segments: [TranscriptSegment], startingAt start: Int) -> [TranscriptSegment] {
        let delta = start - 1
        return segments.map { segment in
            var copy = segment
            if let speaker = segment.speaker {
                if let number = speakerNumber(speaker) {
                    copy.speaker = "Speaker \(number + delta)"
                }
            } else {
                copy.speaker = "Speaker \(start)"
            }
            return copy
        }
    }

    /// Concatenates per-stream segment groups and stable-sorts them by timestamp.
    /// Both recorders start together at t=0, so timestamps are directly comparable
    /// across streams. Ties keep their original relative order (group order, then
    /// position) so a deterministic transcript is produced.
    public static func merge(_ groups: [[TranscriptSegment]]) -> [TranscriptSegment] {
        let flattened = groups.flatMap { $0 }
        return flattened.enumerated()
            .sorted { lhs, rhs in
                if lhs.element.timestamp != rhs.element.timestamp {
                    return lhs.element.timestamp < rhs.element.timestamp
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    /// Parses the trailing integer from a "Speaker N" label, or nil if the label
    /// does not follow that pattern.
    static func speakerNumber(_ label: String) -> Int? {
        let prefix = "Speaker "
        guard label.hasPrefix(prefix) else { return nil }
        return Int(label.dropFirst(prefix.count))
    }
}
