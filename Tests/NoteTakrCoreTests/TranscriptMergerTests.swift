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

    func testPromoteAnchoredSpeakerUsesMicSpeechWindows() {
        let segments = [
            TranscriptSegment(timestamp: 0, speaker: "Speaker 1", text: "Podcast intro"),
            TranscriptSegment(timestamp: 12, speaker: "Speaker 2", text: "My response"),
            TranscriptSegment(timestamp: 24, speaker: "Speaker 1", text: "Podcast continues"),
        ]
        let spans = [
            SpeakerSpan(speakerId: "podcast", start: 0, end: 9),
            SpeakerSpan(speakerId: "me", start: 10, end: 16),
            SpeakerSpan(speakerId: "podcast", start: 21, end: 30),
        ]
        let windows = [TranscriptMerger.SpeechWindow(start: 10.5, end: 15.5)]

        let result = TranscriptMerger.promoteAnchoredSpeaker(
            in: segments,
            speakerSpans: spans,
            anchorWindows: windows
        )

        XCTAssertEqual(result?.match.speaker, "Speaker 2")
        XCTAssertEqual(result?.segments.map(\.speaker), [
            "Speaker 2", "Speaker 1 (You)", "Speaker 2",
        ])
    }

    func testPromoteAnchoredSpeakerCanLimitPrimaryLabelToAnchoredTurns() {
        let segments = [
            TranscriptSegment(timestamp: 12, speaker: "Speaker 2", text: "My response"),
            TranscriptSegment(timestamp: 40, speaker: "Speaker 2", text: "Misclustered podcast"),
            TranscriptSegment(timestamp: 50, speaker: "Speaker 1", text: "Podcast continues"),
        ]
        let spans = [
            SpeakerSpan(speakerId: "podcast", start: 0, end: 10),
            SpeakerSpan(speakerId: "me", start: 10, end: 15),
            SpeakerSpan(speakerId: "me", start: 39, end: 44),
            SpeakerSpan(speakerId: "podcast", start: 49, end: 55),
        ]
        let windows = [TranscriptMerger.SpeechWindow(start: 10.5, end: 14.5)]

        let result = TranscriptMerger.promoteAnchoredSpeaker(
            in: segments,
            speakerSpans: spans,
            anchorWindows: windows,
            requireAnchorOverlapForPrimary: true,
            anchorTolerance: 1.0
        )

        XCTAssertEqual(result?.match.speaker, "Speaker 2")
        XCTAssertEqual(result?.segments.map(\.speaker), [
            "Speaker 1 (You)", "Speaker 2", "Speaker 3",
        ])
    }

    func testAnchoredSpeakerAvoidsAlwaysTalkingSpeaker() {
        let spans = [
            SpeakerSpan(speakerId: "podcast", start: 0, end: 100),
            SpeakerSpan(speakerId: "me", start: 20, end: 27),
            SpeakerSpan(speakerId: "me", start: 60, end: 67),
        ]
        let windows = [
            TranscriptMerger.SpeechWindow(start: 20, end: 26),
            TranscriptMerger.SpeechWindow(start: 60, end: 66),
        ]

        let match = TranscriptMerger.anchoredPrimarySpeaker(
            speakerSpans: spans,
            anchorWindows: windows
        )

        XCTAssertEqual(match?.speaker, "Speaker 2")
        XCTAssertGreaterThan(match?.speakerCoverage ?? 0, 0.8)
    }

    func testAnchoredSpeakerRequiresEnoughCoverage() {
        let spans = [
            SpeakerSpan(speakerId: "podcast", start: 0, end: 20),
            SpeakerSpan(speakerId: "maybeMe", start: 3, end: 4),
        ]
        let windows = [TranscriptMerger.SpeechWindow(start: 3, end: 8)]

        let result = TranscriptMerger.promoteAnchoredSpeaker(
            in: [TranscriptSegment(timestamp: 3, speaker: "Speaker 2", text: "too little")],
            speakerSpans: spans,
            anchorWindows: windows
        )

        XCTAssertNil(result)
    }

    func testMicrophoneOnlySpeechWindowsSubtractSystemAudioBleed() {
        let microphone = [
            TranscriptMerger.SpeechWindow(start: 10, end: 14),
            TranscriptMerger.SpeechWindow(start: 20, end: 26),
            TranscriptMerger.SpeechWindow(start: 40, end: 45),
        ]
        let system = [
            TranscriptMerger.SpeechWindow(start: 19, end: 27),
            TranscriptMerger.SpeechWindow(start: 41, end: 42),
        ]

        let result = TranscriptMerger.microphoneOnlySpeechWindows(
            microphoneWindows: microphone,
            systemAudioWindows: system,
            systemPadding: 0,
            minDuration: 0.5
        )

        XCTAssertEqual(result, [
            TranscriptMerger.SpeechWindow(start: 10, end: 14),
            TranscriptMerger.SpeechWindow(start: 40, end: 41),
            TranscriptMerger.SpeechWindow(start: 42, end: 45),
        ])
    }

    func testSpeakerNumberParsing() {
        XCTAssertEqual(TranscriptMerger.speakerNumber("Speaker 1"), 1)
        XCTAssertEqual(TranscriptMerger.speakerNumber("Speaker 42"), 42)
        XCTAssertNil(TranscriptMerger.speakerNumber("Speaker 1 (You)"))
        XCTAssertNil(TranscriptMerger.speakerNumber("Alice"))
    }
}
