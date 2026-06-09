import Foundation

/// A user-editable prompt template that drives summarization. The `prompt` is the
/// system instruction sent to the model; the transcript is supplied separately as
/// the user message.
public struct SummaryTemplate: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var prompt: String
    public var isBuiltIn: Bool

    public init(id: UUID = UUID(), name: String, prompt: String, isBuiltIn: Bool = false) {
        self.id = id
        self.name = name
        self.prompt = prompt
        self.isBuiltIn = isBuiltIn
    }
}

public extension SummaryTemplate {
    /// Seed templates created on first launch. All are editable; built-ins can be
    /// reset rather than only deleted. Stable ids let `activeTemplateID` survive a
    /// reseed.
    static let defaults: [SummaryTemplate] = [
        SummaryTemplate(
            id: UUID(uuidString: "11111111-0000-0000-0000-000000000001")!,
            name: "Meeting Summary",
            prompt: """
            You are a meticulous meeting assistant. Summarize the following meeting \
            transcript into clear, well-structured notes. Start with a 2-3 sentence \
            overview, then use sections with headings for the main topics discussed. \
            Use the speaker labels to attribute points where helpful. Keep it concise \
            and factual — do not invent details that are not in the transcript.
            """,
            isBuiltIn: true
        ),
        SummaryTemplate(
            id: UUID(uuidString: "11111111-0000-0000-0000-000000000002")!,
            name: "Action Items & Decisions",
            prompt: """
            You are a meeting assistant focused on outcomes. From the following \
            transcript, extract two markdown sections: "## Decisions" listing every \
            decision that was made, and "## Action Items" listing each task as a \
            checkbox with the owner in bold when it can be inferred (e.g. "- [ ] \
            **Alice**: send the report"). If a section has no items, write "None". \
            Do not invent owners or tasks that are not supported by the transcript.
            """,
            isBuiltIn: true
        ),
        SummaryTemplate(
            id: UUID(uuidString: "11111111-0000-0000-0000-000000000003")!,
            name: "Detailed Notes",
            prompt: """
            You are a thorough note-taker. Produce detailed, chronological notes from \
            the following meeting transcript. Capture the flow of the discussion, key \
            points raised by each speaker, questions and answers, and any numbers, \
            dates, or names mentioned. Use bullet points grouped under topic headings. \
            Preserve nuance and stay faithful to what was actually said.
            """,
            isBuiltIn: true
        ),
    ]
}
