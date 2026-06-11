import Foundation

// MARK: - TranscriptSource

public enum TranscriptSource: Equatable, Hashable, Codable {
    case mic
    case systemAudio
}

// MARK: - SpeakerResolution

public enum SpeakerResolution: Equatable {
    case confirmed(String)
    case uncertain(guess: String) // shows as "Speaker · most likely <guess>"
}

// MARK: - TranscriptMerger

public struct TranscriptMerger {

    // MARK: - Two-stream merge

    /// Merges mic and system-audio streams chronologically by start time.
    /// Overlap: earlier start first; equal timestamps → mic before system-audio.
    /// In-person: mic only (system-audio stream is ignored).
    public static func merge(
        mic: [RawSegment],
        systemAudio: [RawSegment],
        inPerson: Bool = false
    ) -> [RawSegment] {
        if inPerson {
            return mic.sorted { $0.timestamp < $1.timestamp }
        }
        let taggedMic = mic.map {
            RawSegment(speaker: $0.speaker, timestamp: $0.timestamp, text: $0.text, source: .mic)
        }
        let taggedSystem = systemAudio.map {
            RawSegment(speaker: $0.speaker, timestamp: $0.timestamp, text: $0.text, source: .systemAudio)
        }
        var combined = taggedMic + taggedSystem
        combined.sort {
            if $0.timestamp != $1.timestamp { return $0.timestamp < $1.timestamp }
            return $0.source == .mic && $1.source == .systemAudio
        }
        return combined
    }

    // MARK: - Speaker naming

    /// Infer speaker→name mapping from stream structure.
    /// Single speaker per stream → confirmed name; otherwise no mapping.
    public static func inferSpeakerNames(
        micSegments: [RawSegment],
        systemAudioSegments: [RawSegment],
        userName: String?,
        participants: [Participant]
    ) -> [String: SpeakerResolution] {
        var mapping: [String: SpeakerResolution] = [:]

        let micSpeakers = Set(micSegments.compactMap { $0.speaker })
        let systemSpeakers = Set(systemAudioSegments.compactMap { $0.speaker })

        if micSpeakers.count == 1, let id = micSpeakers.first {
            mapping[id] = .confirmed(userName ?? "You")
        }

        if systemSpeakers.count == 1, let id = systemSpeakers.first {
            let name = participants.first?.name ?? "Speaker 2"
            mapping[id] = .confirmed(name)
        }

        return mapping
    }

    // MARK: - Copy as markdown

    /// Renders turns as markdown: **Speaker:** text\n\n...
    /// nameOverrides take precedence over speakerResolutions.
    public static func copyAsMarkdown(
        turns: [DisplaySegment],
        speakerResolutions: [String: SpeakerResolution] = [:],
        nameOverrides: [String: String] = [:]
    ) -> String {
        turns.map { turn in
            let id = turn.speaker ?? ""
            let name: String
            if let override = nameOverrides[id], !override.isEmpty {
                name = override
            } else if let res = speakerResolutions[id] {
                switch res {
                case .confirmed(let n): name = n
                case .uncertain(let g): name = "Speaker (most likely \(g))"
                }
            } else {
                name = id.isEmpty ? "Unknown" : id
            }
            return "**\(name):** \(turn.text)"
        }.joined(separator: "\n\n")
    }
}
