import XCTest
@testable import NoteTakrCore

final class TranscriptAssemblerTests: XCTestCase {

    func testNoSpeakersProducesSingleSegment() {
        let words = [
            TimedWord(text: "Hello", start: 1.0, end: 1.5),
            TimedWord(text: "world", start: 1.5, end: 2.0),
        ]
        let segments = TranscriptAssembler.assemble(words: words, speakerSpans: [])
        XCTAssertEqual(segments.count, 1)
        XCTAssertNil(segments[0].speaker)
        XCTAssertEqual(segments[0].text, "Hello world")
        XCTAssertEqual(segments[0].timestamp, 1.0)
    }

    func testGroupsConsecutiveWordsBySpeaker() {
        let words = [
            TimedWord(text: "Hello", start: 0.0, end: 0.5),
            TimedWord(text: "there", start: 0.5, end: 1.0),
            TimedWord(text: "Hi", start: 2.0, end: 2.5),
            TimedWord(text: "back", start: 2.5, end: 3.0),
        ]
        let spans = [
            SpeakerSpan(speakerId: "spk_b", start: 1.6, end: 3.2),
            SpeakerSpan(speakerId: "spk_a", start: 0.0, end: 1.5),
        ]
        let segments = TranscriptAssembler.assemble(words: words, speakerSpans: spans)
        XCTAssertEqual(segments.count, 2)
        // Labels are assigned by first appearance along the timeline (spk_a starts first).
        XCTAssertEqual(segments[0].speaker, "Speaker 1")
        XCTAssertEqual(segments[0].text, "Hello there")
        XCTAssertEqual(segments[1].speaker, "Speaker 2")
        XCTAssertEqual(segments[1].text, "Hi back")
    }

    func testWordWithoutOverlapAttributedToNearestSpeaker() {
        let words = [TimedWord(text: "Umm", start: 5.0, end: 5.2)]
        let spans = [
            SpeakerSpan(speakerId: "a", start: 0.0, end: 1.0),
            SpeakerSpan(speakerId: "b", start: 4.0, end: 4.8),
        ]
        let segments = TranscriptAssembler.assemble(words: words, speakerSpans: spans)
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].speaker, "Speaker 2") // nearest span is "b"
    }

    func testApplyBoostReplacesSingleWordPreservingPunctuation() {
        let words = [
            TimedWord(text: "Try", start: 0.0, end: 0.3),
            TimedWord(text: "noatakr,", start: 0.3, end: 0.9),
        ]
        let boosted = TranscriptAssembler.applyBoost(
            to: words,
            replacements: [WordReplacement(original: "noatakr", replacement: "NoteTakr")]
        )
        XCTAssertEqual(boosted.map(\.text), ["Try", "NoteTakr,"])
        XCTAssertEqual(boosted[1].start, 0.3) // timing preserved
    }

    func testApplyBoostReplacesMultiWordPhrase() {
        let words = [
            TimedWord(text: "use", start: 0.0, end: 0.3),
            TimedWord(text: "tensor", start: 0.3, end: 0.6),
            TimedWord(text: "art", start: 0.6, end: 0.9),
        ]
        let boosted = TranscriptAssembler.applyBoost(
            to: words,
            replacements: [WordReplacement(original: "tensor art", replacement: "TensorRT")]
        )
        XCTAssertEqual(boosted.map(\.text), ["use", "TensorRT"])
    }

    func testSpeakerLabelsByFirstAppearance() {
        let spans = [
            SpeakerSpan(speakerId: "z", start: 5.0, end: 6.0),
            SpeakerSpan(speakerId: "y", start: 0.0, end: 1.0),
            SpeakerSpan(speakerId: "z", start: 7.0, end: 8.0),
        ]
        let labels = TranscriptAssembler.speakerLabels(for: spans)
        XCTAssertEqual(labels["y"], "Speaker 1")
        XCTAssertEqual(labels["z"], "Speaker 2")
    }

    func testFallbackSplitsCoarseTranscriptAcrossSpeakerRuns() {
        let spans = [
            SpeakerSpan(speakerId: "moderator", start: 0.0, end: 2.0),
            SpeakerSpan(speakerId: "panelist", start: 2.0, end: 4.0),
        ]

        let segments = TranscriptAssembler.assembleFallback(
            text: "Welcome everyone Okay thanks",
            speakerSpans: spans
        )

        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[0].speaker, "Speaker 1")
        XCTAssertEqual(segments[0].text, "Welcome everyone")
        XCTAssertEqual(segments[1].speaker, "Speaker 2")
        XCTAssertEqual(segments[1].text, "Okay thanks")
    }
}
