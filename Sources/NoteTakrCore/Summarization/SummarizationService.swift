import Foundation
import NoteTakrKit

/// Turns a transcribed session into a summary by prompting an OpenRouter model.
/// The active template supplies the system instruction; the rendered transcript
/// (plus any linked event title, participants, and user name) is the user message.
public final class SummarizationService: @unchecked Sendable {
    private let client: OpenRouterClient

    public init(client: OpenRouterClient = OpenRouterClient()) {
        self.client = client
    }

    public func summarize(
        session: MeetingSession,
        template: SummaryTemplate,
        modelSlug: String,
        apiKey: String,
        userName: String? = nil
    ) async throws -> String {
        let messages = [
            OpenRouterMessage(role: "system", content: template.prompt),
            OpenRouterMessage(role: "user", content: Self.renderUserMessage(for: session, userName: userName)),
        ]
        return try await client.complete(apiKey: apiKey, model: modelSlug, messages: messages)
    }

    /// Renders the transcript and meeting context into the user message.
    /// Delegates to SummarizationPromptBuilder so the logic is Linux-testable.
    static func renderUserMessage(for session: MeetingSession, userName: String? = nil) -> String {
        let title = session.linkedEventTitle?.isEmpty == false
            ? session.linkedEventTitle!
            : session.title

        let kitParticipants = session.participants.map {
            NoteTakrKit.Participant(name: $0.name, email: $0.email)
        }

        let segments = session.transcriptSegments.map {
            SummarizationSegment(speaker: $0.speaker, timestamp: $0.timestamp, text: $0.text)
        }

        return SummarizationPromptBuilder.buildUserMessage(
            title: title,
            participants: kitParticipants,
            userName: userName,
            segments: segments
        )
    }
}
