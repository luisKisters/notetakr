import XCTest
@testable import NoteTakrCore

final class TranscriptMergerTests: XCTestCase {

    func testForceSingleSpeakerRelabelsEverySegment() {
        let segments = [
            TranscriptSegment(timestamp: 0, speaker: "Speaker 1", text: "Hello"),
            TranscriptSegment(timestamp: 2, speaker: "Speaker 2", text: "there"),
            TranscriptSegment(timestamp: 4, speaker: nil, text: "again"),
        ]
        let result = TranscriptMerger.forceSingleSpeaker(segments, label: "Speaker 1 (You)")
        XCTAssertEqual(result.map(\.speaker), ["Speaker 1 (You)", "Speaker 1 (You)", "Speaker 1 (You)"])
        XCTAssertEqual(result.map(\.text), ["Hello", "there", "again"])
        XCTAssertEqual(result.map(\.timestamp), [0, 2, 4])
    }

    func testOffsetSpeakersShiftsNumberedLabels() {
        let segments = [
            TranscriptSegment(timestamp: 0, speaker: "Speaker 1", text: "a"),
            TranscriptSegment(timestamp: 1, speaker: "Speaker 2", text: "b"),
            TranscriptSegment(timestamp: 2, speaker: "Speaker 1", text: "c"),
        ]
        let result = TranscriptMerger.offsetSpeakers(segments, startingAt: 2)
        XCTAssertEqual(result.map(\.speaker), ["Speaker 2", "Speaker 3", "Speaker 2"])
    }

    func testOffsetSpeakersLabelsUndiarizedSegment() {
        let segments = [TranscriptSegment(timestamp: 0, speaker: nil, text: "mono")]
        let result = TranscriptMerger.offsetSpeakers(segments, startingAt: 2)
        XCTAssertEqual(result[0].speaker, "Speaker 2")
    }

    func testMergeOrdersByTimestampAcrossGroups() {
        let mic = [
            TranscriptSegment(timestamp: 0, speaker: "Speaker 1 (You)", text: "Hi everyone"),
            TranscriptSegment(timestamp: 6, speaker: "Speaker 1 (You)", text: "Let's begin"),
        ]
        let system = [
            TranscriptSegment(timestamp: 3, speaker: "Speaker 2", text: "Hello"),
            TranscriptSegment(timestamp: 9, speaker: "Speaker 3", text: "Sounds good"),
        ]
        let merged = TranscriptMerger.merge([mic, system])
        XCTAssertEqual(merged.map(\.timestamp), [0, 3, 6, 9])
        XCTAssertEqual(merged.map(\.speaker), [
            "Speaker 1 (You)", "Speaker 2", "Speaker 1 (You)", "Speaker 3",
        ])
        XCTAssertEqual(merged.map(\.text), ["Hi everyone", "Hello", "Let's begin", "Sounds good"])
    }

    func testMergeIsStableForEqualTimestamps() {
        let groupA = [TranscriptSegment(timestamp: 5, speaker: "Speaker 1 (You)", text: "first")]
        let groupB = [TranscriptSegment(timestamp: 5, speaker: "Speaker 2", text: "second")]
        let merged = TranscriptMerger.merge([groupA, groupB])
        XCTAssertEqual(merged.map(\.text), ["first", "second"])
    }

    func testFullMicAndSystemMergePipeline() {
        // Simulate per-stream assembler output and run it through the full
        // mic-collapse + system-offset + merge pipeline.
        let micSegments = TranscriptMerger.forceSingleSpeaker(
            [TranscriptSegment(timestamp: 0, speaker: nil, text: "Starting the call")],
            label: TranscriptMerger.primarySpeakerLabel
        )
        let systemSegments = TranscriptMerger.offsetSpeakers(
            [
                TranscriptSegment(timestamp: 2, speaker: "Speaker 1", text: "Good morning"),
                TranscriptSegment(timestamp: 5, speaker: "Speaker 2", text: "Morning"),
            ],
            startingAt: 2
        )
        let merged = TranscriptMerger.merge([micSegments, systemSegments])
        XCTAssertEqual(merged.map(\.speaker), ["Speaker 1 (You)", "Speaker 2", "Speaker 3"])
        XCTAssertEqual(merged.map(\.text), ["Starting the call", "Good morning", "Morning"])
    }

    func testSpeakerNumberParsing() {
        XCTAssertEqual(TranscriptMerger.speakerNumber("Speaker 1"), 1)
        XCTAssertEqual(TranscriptMerger.speakerNumber("Speaker 42"), 42)
        XCTAssertNil(TranscriptMerger.speakerNumber("Speaker 1 (You)"))
        XCTAssertNil(TranscriptMerger.speakerNumber("Alice"))
    }
}
