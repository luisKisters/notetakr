import Foundation

// MARK: - SummarizationSegment

/// A transcript segment used as input to prompt construction.
/// Defined here so the builder is usable from both NoteTakrCore and tests without
/// pulling in the Core's richer TranscriptSegment type.
public struct SummarizationSegment: Equatable {
    public var speaker: String?
    public var timestamp: TimeInterval
    public var text: String

    public init(speaker: String?, timestamp: TimeInterval, text: String) {
        self.speaker = speaker
        self.timestamp = timestamp
        self.text = text
    }
}

// MARK: - SummarizationConfig

/// Captures the model selection and user-identity context used when generating a summary.
/// Keeping this in NoteTakrKit makes it unit-testable on Linux.
public struct SummarizationConfig: Equatable {
    /// The OpenRouter model slug that will be sent on the wire (e.g. "moonshotai/kimi-k2").
    public var modelSlug: String
    /// The local user's display name — used in the prompt so the model can attribute the
    /// microphone speaker correctly.
    public var userName: String?

    public init(modelSlug: String, userName: String? = nil) {
        self.modelSlug = modelSlug
        self.userName = userName
    }
}

// MARK: - SummarizationPromptBuilder

/// Builds the user-turn message that accompanies the system-instruction template.
/// Pure logic — no I/O, no framework dependencies — so it can be unit-tested on Linux.
public struct SummarizationPromptBuilder {

    /// Constructs the user message containing meeting context and transcript.
    ///
    /// The message always includes a speaker-inference instruction so the model knows
    /// to use "Speaker N · most likely <name>" rather than guessing a definite name.
    public static func buildUserMessage(
        title: String,
        participants: [Participant],
        userName: String?,
        segments: [SummarizationSegment]
    ) -> String {
        var lines: [String] = []

        if !title.isEmpty {
            lines.append("Meeting: \(title)")
        }

        if let name = userName, !name.isEmpty {
            lines.append("Note-taker: \(name)")
        }

        if !participants.isEmpty {
            let formatted = participants.map { p -> String in
                if let email = p.email, !email.isEmpty {
                    return "\(p.name) <\(email)>"
                }
                return p.name
            }
            lines.append("Participants: \(formatted.joined(separator: ", "))")
        }

        if !lines.isEmpty {
            lines.append("")
        }

        lines.append(
            "Speaker inference: when a speaker label is ambiguous (e.g. \"Speaker 1\", \"Speaker 2\")," +
            " infer who it most likely is from the participants and context above." +
            " When confident, use their real name." +
            " When uncertain, label them as \"Speaker N \u{00B7} most likely <name>\" rather than guessing."
        )
        lines.append("")

        lines.append("Transcript:")
        if segments.isEmpty {
            lines.append("(no speech was transcribed)")
        } else {
            for segment in segments {
                let total = max(0, Int(segment.timestamp))
                let ts = String(format: "%d:%02d", total / 60, total % 60)
                if let speaker = segment.speaker {
                    lines.append("[\(ts)] \(speaker): \(segment.text)")
                } else {
                    lines.append("[\(ts)] \(segment.text)")
                }
            }
        }

        return lines.joined(separator: "\n")
    }
}
