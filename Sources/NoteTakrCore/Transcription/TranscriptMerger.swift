import Foundation

/// Pure logic for combining several independently-transcribed audio streams
/// (e.g. the microphone and the system-audio capture) into one timeline-ordered,
/// speaker-labelled transcript. Kept free of FluidAudio and any I/O so it can be
/// unit-tested deterministically, mirroring the style of `TranscriptAssembler`.
public enum TranscriptMerger {

    /// Label applied to the local microphone stream — the person running the app.
    public static let primarySpeakerLabel = "Speaker 1 (You)"

    /// A speech interval detected from the local microphone track. These windows
    /// are used as timing anchors when a mixed microphone+system transcript needs
    /// to decide which diarized speaker is the user.
    public struct SpeechWindow: Equatable, Sendable {
        public var start: TimeInterval
        public var end: TimeInterval

        public init(start: TimeInterval, end: TimeInterval) {
            self.start = start
            self.end = end
        }

        var duration: TimeInterval {
            max(0, end - start)
        }
    }

    /// Confidence details for the diarized speaker matched to the mic speech.
    public struct SpeakerAnchorMatch: Equatable, Sendable {
        public var speaker: String
        public var anchorCoverage: Double
        public var speakerCoverage: Double
        public var score: Double
        public var overlapDuration: TimeInterval

        public init(
            speaker: String,
            anchorCoverage: Double,
            speakerCoverage: Double,
            score: Double,
            overlapDuration: TimeInterval
        ) {
            self.speaker = speaker
            self.anchorCoverage = anchorCoverage
            self.speakerCoverage = speakerCoverage
            self.score = score
            self.overlapDuration = overlapDuration
        }
    }

    public struct AnchoredSpeakerRelabelResult: Equatable, Sendable {
        public var segments: [TranscriptSegment]
        public var match: SpeakerAnchorMatch

        public init(segments: [TranscriptSegment], match: SpeakerAnchorMatch) {
            self.segments = segments
            self.match = match
        }
    }

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

    /// Uses microphone VAD windows to find the diarized speaker that most
    /// consistently overlaps the user's speech, then promotes that speaker to
    /// "Speaker 1 (You)" and renumbers everyone else from "Speaker 2".
    public static func promoteAnchoredSpeaker(
        in segments: [TranscriptSegment],
        speakerSpans: [SpeakerSpan],
        anchorWindows: [SpeechWindow],
        minAnchorCoverage: Double = 0.60,
        minSpeakerCoverage: Double = 0.18,
        minScore: Double = 0.42,
        minScoreLead: Double = 0.05,
        requireAnchorOverlapForPrimary: Bool = false,
        anchorTolerance: TimeInterval = 2.0
    ) -> AnchoredSpeakerRelabelResult? {
        let windows = mergedWindows(anchorWindows)
        guard let match = anchoredPrimarySpeaker(
            speakerSpans: speakerSpans,
            anchorWindows: windows,
            minAnchorCoverage: minAnchorCoverage,
            minSpeakerCoverage: minSpeakerCoverage,
            minScore: minScore,
            minScoreLead: minScoreLead
        ) else {
            return nil
        }

        return AnchoredSpeakerRelabelResult(
            segments: promoteSpeaker(
                match.speaker,
                in: segments,
                anchorWindows: requireAnchorOverlapForPrimary ? windows : nil,
                anchorTolerance: anchorTolerance
            ),
            match: match
        )
    }

    public static func anchoredPrimarySpeaker(
        speakerSpans: [SpeakerSpan],
        anchorWindows: [SpeechWindow],
        minAnchorCoverage: Double = 0.60,
        minSpeakerCoverage: Double = 0.18,
        minScore: Double = 0.42,
        minScoreLead: Double = 0.05
    ) -> SpeakerAnchorMatch? {
        let windows = mergedWindows(anchorWindows)
        let totalAnchorDuration = windows.reduce(0) { $0 + $1.duration }
        guard totalAnchorDuration > 0 else { return nil }

        let labels = TranscriptAssembler.speakerLabels(for: speakerSpans)
        var totalsBySpeaker: [String: TimeInterval] = [:]
        var overlapBySpeaker: [String: TimeInterval] = [:]

        for span in speakerSpans where span.end > span.start {
            guard let label = labels[span.speakerId] else { continue }
            let duration = span.end - span.start
            totalsBySpeaker[label, default: 0] += duration
            overlapBySpeaker[label, default: 0] += overlapDuration(
                start: span.start,
                end: span.end,
                windows: windows
            )
        }

        let candidates = totalsBySpeaker.compactMap { speaker, totalDuration -> SpeakerAnchorMatch? in
            guard totalDuration > 0 else { return nil }
            let overlap = overlapBySpeaker[speaker, default: 0]
            guard overlap > 0 else { return nil }
            let anchorCoverage = overlap / totalAnchorDuration
            let speakerCoverage = overlap / totalDuration
            let score = harmonicMean(anchorCoverage, speakerCoverage)
            return SpeakerAnchorMatch(
                speaker: speaker,
                anchorCoverage: anchorCoverage,
                speakerCoverage: speakerCoverage,
                score: score,
                overlapDuration: overlap
            )
        }
        .sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.anchorCoverage > $1.anchorCoverage
        }

        guard let best = candidates.first,
              best.anchorCoverage >= minAnchorCoverage,
              best.speakerCoverage >= minSpeakerCoverage,
              best.score >= minScore else {
            return nil
        }
        if candidates.count > 1, best.score - candidates[1].score < minScoreLead {
            return nil
        }
        return best
    }

    /// Removes system-audio speech windows from microphone VAD windows. This
    /// filters out podcast/meeting audio that leaked into the local microphone,
    /// leaving higher-confidence "the user was speaking here" anchors.
    public static func microphoneOnlySpeechWindows(
        microphoneWindows: [SpeechWindow],
        systemAudioWindows: [SpeechWindow],
        systemPadding: TimeInterval = 0.35,
        minDuration: TimeInterval = 0.30
    ) -> [SpeechWindow] {
        let microphone = mergedWindows(microphoneWindows)
        let system = mergedWindows(systemAudioWindows.map {
            SpeechWindow(
                start: max(0, $0.start - systemPadding),
                end: $0.end + systemPadding
            )
        })
        guard !microphone.isEmpty else { return [] }
        guard !system.isEmpty else {
            return microphone.filter { $0.duration >= minDuration }
        }

        var result: [SpeechWindow] = []
        for window in microphone {
            var remaining = [window]
            for exclusion in system {
                remaining = remaining.flatMap { subtract(exclusion, from: $0) }
                if remaining.isEmpty { break }
            }
            result.append(contentsOf: remaining.filter { $0.duration >= minDuration })
        }
        return mergedWindows(result)
    }

    /// Parses the trailing integer from a "Speaker N" label, or nil if the label
    /// does not follow that pattern.
    static func speakerNumber(_ label: String) -> Int? {
        let prefix = "Speaker "
        guard label.hasPrefix(prefix) else { return nil }
        return Int(label.dropFirst(prefix.count))
    }

    private static func promoteSpeaker(
        _ primarySpeaker: String,
        in segments: [TranscriptSegment],
        anchorWindows: [SpeechWindow]? = nil,
        anchorTolerance: TimeInterval = 2.0
    ) -> [TranscriptSegment] {
        var labels: [String: String] = anchorWindows == nil ? [primarySpeaker: primarySpeakerLabel] : [:]
        var nextSpeakerNumber = 2

        return segments.map { segment in
            var copy = segment
            guard let speaker = segment.speaker else {
                if labels[""] == nil {
                    labels[""] = "Speaker \(nextSpeakerNumber)"
                    nextSpeakerNumber += 1
                }
                copy.speaker = labels[""]
                return copy
            }

            let isAnchoredPrimary = speaker == primarySpeaker
                && (anchorWindows == nil || timestamp(segment.timestamp, overlaps: anchorWindows ?? [], tolerance: anchorTolerance))
            if isAnchoredPrimary {
                copy.speaker = primarySpeakerLabel
                return copy
            }

            if labels[speaker] == nil || labels[speaker] == primarySpeakerLabel {
                labels[speaker] = "Speaker \(nextSpeakerNumber)"
                nextSpeakerNumber += 1
            }
            copy.speaker = labels[speaker]
            return copy
        }
    }

    private static func mergedWindows(_ windows: [SpeechWindow]) -> [SpeechWindow] {
        let sorted = windows
            .filter { $0.end > $0.start }
            .sorted {
                if $0.start != $1.start { return $0.start < $1.start }
                return $0.end < $1.end
            }
        guard var current = sorted.first else { return [] }
        var result: [SpeechWindow] = []

        for window in sorted.dropFirst() {
            if window.start <= current.end {
                current.end = max(current.end, window.end)
            } else {
                result.append(current)
                current = window
            }
        }
        result.append(current)
        return result
    }

    private static func subtract(_ exclusion: SpeechWindow, from window: SpeechWindow) -> [SpeechWindow] {
        let overlapStart = max(window.start, exclusion.start)
        let overlapEnd = min(window.end, exclusion.end)
        guard overlapEnd > overlapStart else { return [window] }

        var pieces: [SpeechWindow] = []
        if window.start < overlapStart {
            pieces.append(SpeechWindow(start: window.start, end: overlapStart))
        }
        if overlapEnd < window.end {
            pieces.append(SpeechWindow(start: overlapEnd, end: window.end))
        }
        return pieces
    }

    private static func timestamp(
        _ timestamp: TimeInterval,
        overlaps windows: [SpeechWindow],
        tolerance: TimeInterval
    ) -> Bool {
        windows.contains { window in
            timestamp >= window.start - tolerance && timestamp <= window.end + tolerance
        }
    }

    private static func overlapDuration(
        start: TimeInterval,
        end: TimeInterval,
        windows: [SpeechWindow]
    ) -> TimeInterval {
        windows.reduce(0) { total, window in
            let overlapStart = max(start, window.start)
            let overlapEnd = min(end, window.end)
            return total + max(0, overlapEnd - overlapStart)
        }
    }

    private static func harmonicMean(_ a: Double, _ b: Double) -> Double {
        guard a > 0, b > 0 else { return 0 }
        return 2 * a * b / (a + b)
    }
}
