import Foundation

/// Turns a transcribed session into a summary by prompting an OpenRouter model.
/// The active template supplies the system instruction; the rendered transcript
/// (plus any linked event title and participants) is the user message.
public final class SummarizationService: @unchecked Sendable {
    private let client: OpenRouterClient

    public init(client: OpenRouterClient = OpenRouterClient()) {
        self.client = client
    }

    public func summarize(
        session: MeetingSession,
        template: SummaryTemplate,
        modelSlug: String,
        apiKey: String
    ) async throws -> String {
        let messages = [
            OpenRouterMessage(role: "system", content: template.prompt),
            OpenRouterMessage(role: "user", content: Self.renderUserMessage(for: session)),
        ]
        return try await client.complete(apiKey: apiKey, model: modelSlug, messages: messages)
    }

    /// Renders the transcript and any meeting context into the user message.
    static func renderUserMessage(for session: MeetingSession) -> String {
        var lines: [String] = []

        if let eventTitle = session.linkedEventTitle, !eventTitle.isEmpty {
            lines.append("Meeting: \(eventTitle)")
        } else if !session.title.isEmpty {
            lines.append("Meeting: \(session.title)")
        }

        if !session.participants.isEmpty {
            let names = session.participants.map { participant -> String in
                if let email = participant.email, !email.isEmpty {
                    return "\(participant.name) <\(email)>"
                }
                return participant.name
            }
            lines.append("Participants: \(names.joined(separator: ", "))")
        }

        if !lines.isEmpty {
            lines.append("")
        }

        lines.append("Transcript:")
        if session.transcriptSegments.isEmpty {
            lines.append("(no speech was transcribed)")
        } else {
            for segment in session.transcriptSegments {
                let total = Int(segment.timestamp)
                let timestamp = String(format: "%d:%02d", total / 60, total % 60)
                if let speaker = segment.speaker {
                    lines.append("[\(timestamp)] \(speaker): \(segment.text)")
                } else {
                    lines.append("[\(timestamp)] \(segment.text)")
                }
            }
        }

        return lines.joined(separator: "\n")
    }
}
