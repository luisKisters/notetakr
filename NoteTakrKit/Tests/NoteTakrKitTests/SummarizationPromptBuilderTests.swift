import XCTest
@testable import NoteTakrKit

final class SummarizationPromptBuilderTests: XCTestCase {

    // MARK: - Speaker-inference instruction

    func testPromptAlwaysContainsSpeakerInferenceInstruction() {
        let msg = SummarizationPromptBuilder.buildUserMessage(
            title: "Team sync",
            participants: [],
            userName: nil,
            segments: []
        )
        XCTAssertTrue(
            msg.contains("Speaker inference"),
            "Prompt must contain speaker-inference instruction"
        )
    }

    func testPromptContainsMostLikelyWording() {
        let msg = SummarizationPromptBuilder.buildUserMessage(
            title: "Standup",
            participants: [Participant(name: "Alice")],
            userName: "Bob",
            segments: []
        )
        XCTAssertTrue(
            msg.contains("most likely"),
            "Speaker-inference instruction must include 'most likely' wording"
        )
    }

    func testPromptContainsUncertainLabelFormat() {
        let msg = SummarizationPromptBuilder.buildUserMessage(
            title: "Review",
            participants: [],
            userName: nil,
            segments: []
        )
        // Verify the "Speaker N · most likely <name>" pattern is described
        XCTAssertTrue(
            msg.contains("Speaker N"),
            "Instruction must reference the 'Speaker N' placeholder"
        )
    }

    // MARK: - Participant context

    func testPromptContainsParticipantName() {
        let msg = SummarizationPromptBuilder.buildUserMessage(
            title: "Kickoff",
            participants: [Participant(name: "Charlie", email: "charlie@example.com")],
            userName: nil,
            segments: []
        )
        XCTAssertTrue(msg.contains("Charlie"), "Prompt must include participant name")
    }

    func testPromptContainsParticipantEmail() {
        let msg = SummarizationPromptBuilder.buildUserMessage(
            title: "Kickoff",
            participants: [Participant(name: "Charlie", email: "charlie@example.com")],
            userName: nil,
            segments: []
        )
        XCTAssertTrue(msg.contains("charlie@example.com"), "Prompt must include participant email")
    }

    func testPromptContainsMultipleParticipants() {
        let msg = SummarizationPromptBuilder.buildUserMessage(
            title: "All-hands",
            participants: [
                Participant(name: "Alice", email: "alice@co.com"),
                Participant(name: "Bob", email: "bob@co.com"),
            ],
            userName: nil,
            segments: []
        )
        XCTAssertTrue(msg.contains("Alice"), "Must include first participant")
        XCTAssertTrue(msg.contains("Bob"), "Must include second participant")
        XCTAssertTrue(msg.contains("alice@co.com"), "Must include first participant email")
        XCTAssertTrue(msg.contains("bob@co.com"), "Must include second participant email")
    }

    func testParticipantWithoutEmailOmitsEmailAngleBrackets() {
        let msg = SummarizationPromptBuilder.buildUserMessage(
            title: "Chat",
            participants: [Participant(name: "Dana", email: nil)],
            userName: nil,
            segments: []
        )
        XCTAssertTrue(msg.contains("Dana"))
        // The participant line should not include an "<email>" form for Dana
        XCTAssertFalse(msg.contains("Dana <"), "No 'Name <email>' form when email is absent")
    }

    func testNoParticipantsSectionWhenEmpty() {
        let msg = SummarizationPromptBuilder.buildUserMessage(
            title: "Solo",
            participants: [],
            userName: nil,
            segments: []
        )
        XCTAssertFalse(msg.contains("Participants:"), "No 'Participants:' line when list is empty")
    }

    // MARK: - User name context

    func testPromptContainsUserName() {
        let msg = SummarizationPromptBuilder.buildUserMessage(
            title: "1:1",
            participants: [],
            userName: "Eve Smith",
            segments: []
        )
        XCTAssertTrue(msg.contains("Eve Smith"), "Prompt must include the user's own name")
    }

    func testNoNoteTakerLineWhenUserNameIsNil() {
        let msg = SummarizationPromptBuilder.buildUserMessage(
            title: "1:1",
            participants: [],
            userName: nil,
            segments: []
        )
        XCTAssertFalse(msg.contains("Note-taker:"), "No 'Note-taker:' line when userName is nil")
    }

    func testNoNoteTakerLineWhenUserNameIsEmpty() {
        let msg = SummarizationPromptBuilder.buildUserMessage(
            title: "1:1",
            participants: [],
            userName: "",
            segments: []
        )
        XCTAssertFalse(msg.contains("Note-taker:"), "No 'Note-taker:' line when userName is empty")
    }

    // MARK: - Transcript segments

    func testPromptContainsTranscriptHeader() {
        let msg = SummarizationPromptBuilder.buildUserMessage(
            title: "T", participants: [], userName: nil, segments: []
        )
        XCTAssertTrue(msg.contains("Transcript:"), "Must have 'Transcript:' header")
    }

    func testEmptyTranscriptShowsPlaceholder() {
        let msg = SummarizationPromptBuilder.buildUserMessage(
            title: "T", participants: [], userName: nil, segments: []
        )
        XCTAssertTrue(
            msg.contains("(no speech was transcribed)"),
            "Empty transcript must show placeholder"
        )
    }

    func testSegmentSpeakerAndTextIncluded() {
        let seg = SummarizationSegment(speaker: "Speaker 1", timestamp: 65, text: "Hello there")
        let msg = SummarizationPromptBuilder.buildUserMessage(
            title: "T", participants: [], userName: nil, segments: [seg]
        )
        XCTAssertTrue(msg.contains("Speaker 1"), "Segment speaker must appear")
        XCTAssertTrue(msg.contains("Hello there"), "Segment text must appear")
        XCTAssertTrue(msg.contains("[1:05]"), "Timestamp must be formatted as mm:ss")
    }

    func testSegmentWithoutSpeakerOmitsSpeakerLabel() {
        let seg = SummarizationSegment(speaker: nil, timestamp: 5, text: "Ambient sound")
        let msg = SummarizationPromptBuilder.buildUserMessage(
            title: "T", participants: [], userName: nil, segments: [seg]
        )
        XCTAssertTrue(msg.contains("Ambient sound"))
        XCTAssertTrue(msg.contains("[0:05]"))
        // No "null:" or "nil:" should appear
        XCTAssertFalse(msg.contains("nil:"))
        XCTAssertFalse(msg.contains("null:"))
    }

    func testSegmentsAreFormattedWithTimestamp() {
        let segments = [
            SummarizationSegment(speaker: "Alice", timestamp: 0, text: "Start"),
            SummarizationSegment(speaker: "Bob", timestamp: 3661, text: "End"),
        ]
        let msg = SummarizationPromptBuilder.buildUserMessage(
            title: "Long meeting", participants: [], userName: nil, segments: segments
        )
        XCTAssertTrue(msg.contains("[0:00] Alice: Start"))
        XCTAssertTrue(msg.contains("[61:01] Bob: End"))
    }

    // MARK: - SummarizationConfig (model slug is honored)

    func testSummarizationConfigPreservesModelSlug() {
        let config = SummarizationConfig(modelSlug: "anthropic/claude-opus-4.8")
        XCTAssertEqual(config.modelSlug, "anthropic/claude-opus-4.8")
    }

    func testSummarizationConfigPreservesUserName() {
        let config = SummarizationConfig(modelSlug: "moonshotai/kimi-k2", userName: "Grace")
        XCTAssertEqual(config.userName, "Grace")
    }

    func testSummarizationConfigDefaultsUserNameToNil() {
        let config = SummarizationConfig(modelSlug: "some/model")
        XCTAssertNil(config.userName)
    }

    func testSummarizationConfigEquality() {
        let a = SummarizationConfig(modelSlug: "m", userName: "Alice")
        let b = SummarizationConfig(modelSlug: "m", userName: "Alice")
        let c = SummarizationConfig(modelSlug: "other", userName: "Alice")
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    // MARK: - Meeting title

    func testMeetingTitleIncluded() {
        let msg = SummarizationPromptBuilder.buildUserMessage(
            title: "Product Review Q3",
            participants: [],
            userName: nil,
            segments: []
        )
        XCTAssertTrue(msg.contains("Meeting: Product Review Q3"))
    }

    func testEmptyTitleOmitsMeetingLine() {
        let msg = SummarizationPromptBuilder.buildUserMessage(
            title: "",
            participants: [],
            userName: nil,
            segments: []
        )
        XCTAssertFalse(msg.contains("Meeting:"), "No 'Meeting:' line when title is empty")
    }
}
