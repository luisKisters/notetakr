import XCTest
@testable import NoteTakrKit

final class TranscriptMergerTests: XCTestCase {

    // MARK: - Two-stream merge: ordering

    func testMerge_orderedByTimestamp() {
        let mic = [RawSegment(speaker: "A", timestamp: 10, text: "mic later")]
        let sys = [RawSegment(speaker: "B", timestamp: 5, text: "sys earlier")]
        let result = TranscriptMerger.merge(mic: mic, systemAudio: sys)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].text, "sys earlier")
        XCTAssertEqual(result[1].text, "mic later")
    }

    func testMerge_overlapCase_micBeforeSystemOnTie() {
        let mic = [RawSegment(speaker: "A", timestamp: 4, text: "mic")]
        let sys = [RawSegment(speaker: "B", timestamp: 4, text: "sys")]
        let result = TranscriptMerger.merge(mic: mic, systemAudio: sys)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].text, "mic")
        XCTAssertEqual(result[1].text, "sys")
    }

    func testMerge_tagsSourceOnSegments() {
        let mic = [RawSegment(speaker: "A", timestamp: 0, text: "m")]
        let sys = [RawSegment(speaker: "B", timestamp: 1, text: "s")]
        let result = TranscriptMerger.merge(mic: mic, systemAudio: sys)
        XCTAssertEqual(result[0].source, .mic)
        XCTAssertEqual(result[1].source, .systemAudio)
    }

    func testMerge_emptySystemAudio() {
        let mic = [
            RawSegment(speaker: "A", timestamp: 2, text: "hi"),
            RawSegment(speaker: "A", timestamp: 0, text: "hello")
        ]
        let result = TranscriptMerger.merge(mic: mic, systemAudio: [])
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].text, "hello")
        XCTAssertEqual(result[1].text, "hi")
    }

    func testMerge_emptyMic() {
        let sys = [RawSegment(speaker: "B", timestamp: 1, text: "only")]
        let result = TranscriptMerger.merge(mic: [], systemAudio: sys)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].text, "only")
    }

    func testMerge_bothStreamsEmpty_returnsEmpty() {
        let result = TranscriptMerger.merge(mic: [], systemAudio: [])
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - In-person: mic only

    func testMerge_inPerson_micOnly() {
        let mic = [RawSegment(speaker: "A", timestamp: 0, text: "mic only")]
        let sys = [RawSegment(speaker: "B", timestamp: 1, text: "should be excluded")]
        let result = TranscriptMerger.merge(mic: mic, systemAudio: sys, inPerson: true)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].text, "mic only")
    }

    func testMerge_inPerson_sortsMicByTimestamp() {
        let mic = [
            RawSegment(speaker: "A", timestamp: 5, text: "second"),
            RawSegment(speaker: "A", timestamp: 1, text: "first")
        ]
        let result = TranscriptMerger.merge(mic: mic, systemAudio: [], inPerson: true)
        XCTAssertEqual(result[0].text, "first")
        XCTAssertEqual(result[1].text, "second")
    }

    // MARK: - Speaker naming: single speaker per stream

    func testInferNames_singleMicSpeaker_confirmedAsUserName() {
        let mic = [RawSegment(speaker: "SPEAKER_0", timestamp: 0, text: "hi")]
        let result = TranscriptMerger.inferSpeakerNames(
            micSegments: mic, systemAudioSegments: [],
            userName: "Luis", participants: []
        )
        XCTAssertEqual(result["SPEAKER_0"], .confirmed("Luis"))
    }

    func testInferNames_singleMicSpeaker_fallbackToYou() {
        let mic = [RawSegment(speaker: "SPEAKER_0", timestamp: 0, text: "hi")]
        let result = TranscriptMerger.inferSpeakerNames(
            micSegments: mic, systemAudioSegments: [],
            userName: nil, participants: []
        )
        XCTAssertEqual(result["SPEAKER_0"], .confirmed("You"))
    }

    func testInferNames_singleSystemSpeaker_firstParticipant() {
        let sys = [RawSegment(speaker: "SPEAKER_1", timestamp: 0, text: "hello")]
        let participants = [Participant(name: "Sarah", email: "sarah@acme.com")]
        let result = TranscriptMerger.inferSpeakerNames(
            micSegments: [], systemAudioSegments: sys,
            userName: nil, participants: participants
        )
        XCTAssertEqual(result["SPEAKER_1"], .confirmed("Sarah"))
    }

    func testInferNames_singleSystemSpeaker_noParticipants_speaker2() {
        let sys = [RawSegment(speaker: "SPEAKER_1", timestamp: 0, text: "hello")]
        let result = TranscriptMerger.inferSpeakerNames(
            micSegments: [], systemAudioSegments: sys,
            userName: nil, participants: []
        )
        XCTAssertEqual(result["SPEAKER_1"], .confirmed("Speaker 2"))
    }

    func testInferNames_multipleMicSpeakers_noMapping() {
        let mic = [
            RawSegment(speaker: "SPEAKER_0", timestamp: 0, text: "a"),
            RawSegment(speaker: "SPEAKER_1", timestamp: 1, text: "b")
        ]
        let result = TranscriptMerger.inferSpeakerNames(
            micSegments: mic, systemAudioSegments: [],
            userName: "Luis", participants: []
        )
        XCTAssertNil(result["SPEAKER_0"])
        XCTAssertNil(result["SPEAKER_1"])
    }

    func testInferNames_multipleSystemSpeakers_noMapping() {
        let sys = [
            RawSegment(speaker: "SPEAKER_0", timestamp: 0, text: "a"),
            RawSegment(speaker: "SPEAKER_1", timestamp: 1, text: "b")
        ]
        let result = TranscriptMerger.inferSpeakerNames(
            micSegments: [], systemAudioSegments: sys,
            userName: nil, participants: [Participant(name: "Sarah")]
        )
        XCTAssertNil(result["SPEAKER_0"])
        XCTAssertNil(result["SPEAKER_1"])
    }

    func testInferNames_nilSpeakerSegments_ignored() {
        let mic = [
            RawSegment(speaker: nil, timestamp: 0, text: "no speaker"),
            RawSegment(speaker: "SPEAKER_0", timestamp: 1, text: "has speaker")
        ]
        let result = TranscriptMerger.inferSpeakerNames(
            micSegments: mic, systemAudioSegments: [],
            userName: "Luis", participants: []
        )
        XCTAssertEqual(result["SPEAKER_0"], .confirmed("Luis"))
    }

    // MARK: - Copy as markdown

    func testCopyAsMarkdown_emptyTurns_returnsEmptyString() {
        let md = TranscriptMerger.copyAsMarkdown(turns: [])
        XCTAssertEqual(md, "")
    }

    func testCopyAsMarkdown_confirmedSpeaker() {
        let turns = [DisplaySegment(speaker: "SPK_0", startStamp: "0:00", text: "Hello world")]
        let resolutions: [String: SpeakerResolution] = ["SPK_0": .confirmed("Luis")]
        let md = TranscriptMerger.copyAsMarkdown(turns: turns, speakerResolutions: resolutions)
        XCTAssertEqual(md, "**Luis:** Hello world")
    }

    func testCopyAsMarkdown_uncertainSpeaker() {
        let turns = [DisplaySegment(speaker: "SPK_2", startStamp: "0:05", text: "Draft is done")]
        let resolutions: [String: SpeakerResolution] = ["SPK_2": .uncertain(guess: "Tom")]
        let md = TranscriptMerger.copyAsMarkdown(turns: turns, speakerResolutions: resolutions)
        XCTAssertEqual(md, "**Speaker (most likely Tom):** Draft is done")
    }

    func testCopyAsMarkdown_nameOverrideWins() {
        let turns = [DisplaySegment(speaker: "SPK_0", startStamp: "0:00", text: "Hi")]
        let resolutions: [String: SpeakerResolution] = ["SPK_0": .confirmed("Old Name")]
        let overrides: [String: String] = ["SPK_0": "New Name"]
        let md = TranscriptMerger.copyAsMarkdown(turns: turns, speakerResolutions: resolutions, nameOverrides: overrides)
        XCTAssertEqual(md, "**New Name:** Hi")
    }

    func testCopyAsMarkdown_unknownSpeaker_usesRawID() {
        let turns = [DisplaySegment(speaker: "SPEAKER_7", startStamp: "0:00", text: "text")]
        let md = TranscriptMerger.copyAsMarkdown(turns: turns)
        XCTAssertEqual(md, "**SPEAKER_7:** text")
    }

    func testCopyAsMarkdown_nilSpeaker_usesUnknown() {
        let turns = [DisplaySegment(speaker: nil, startStamp: "0:00", text: "text")]
        let md = TranscriptMerger.copyAsMarkdown(turns: turns)
        XCTAssertEqual(md, "**Unknown:** text")
    }

    func testCopyAsMarkdown_multiTurn_joinedWithDoubleNewline() {
        let turns = [
            DisplaySegment(speaker: "A", startStamp: "0:00", text: "First"),
            DisplaySegment(speaker: "B", startStamp: "0:05", text: "Second")
        ]
        let resolutions: [String: SpeakerResolution] = ["A": .confirmed("Alice"), "B": .confirmed("Bob")]
        let md = TranscriptMerger.copyAsMarkdown(turns: turns, speakerResolutions: resolutions)
        XCTAssertEqual(md, "**Alice:** First\n\n**Bob:** Second")
    }

    // MARK: - Rename propagation via nameOverrides

    func testRenamePropagatesToAllTurnsOfSameSpeaker() {
        let turns = [
            DisplaySegment(speaker: "SPK_0", startStamp: "0:00", text: "First turn"),
            DisplaySegment(speaker: "SPK_1", startStamp: "0:10", text: "Other speaker"),
            DisplaySegment(speaker: "SPK_0", startStamp: "0:20", text: "Third turn")
        ]
        var overrides: [String: String] = [:]
        overrides["SPK_0"] = "Luis"
        let md = TranscriptMerger.copyAsMarkdown(turns: turns, nameOverrides: overrides)
        XCTAssertTrue(md.hasPrefix("**Luis:** First turn"))
        XCTAssertTrue(md.contains("**Luis:** Third turn"))
        XCTAssertTrue(md.contains("**SPK_1:** Other speaker"))
    }

    // MARK: - Integration: same-speaker merge + two-stream

    func testIntegration_twoStreams_sameSpeakerMergesAfterInterleave() {
        let mic = [
            RawSegment(speaker: "ME", timestamp: 0, text: "Hello"),
            RawSegment(speaker: "ME", timestamp: 5, text: "world")
        ]
        let sys = [RawSegment(speaker: "OTHER", timestamp: 2, text: "Hi")]
        let merged = TranscriptMerger.merge(mic: mic, systemAudio: sys)
        let grouped = NoteTabsPresenter.groupSegments(merged)
        XCTAssertEqual(grouped.count, 3)
        XCTAssertEqual(grouped[0].speaker, "ME")
        XCTAssertEqual(grouped[0].text, "Hello")
        XCTAssertEqual(grouped[1].speaker, "OTHER")
        XCTAssertEqual(grouped[2].speaker, "ME")
        XCTAssertEqual(grouped[2].text, "world")
    }

    func testIntegration_singleSpeakerPerStream_naming() {
        let mic = [RawSegment(speaker: "SPK_0", timestamp: 0, text: "Hi")]
        let sys = [RawSegment(speaker: "SPK_1", timestamp: 1, text: "Hello")]
        let resolutions = TranscriptMerger.inferSpeakerNames(
            micSegments: mic, systemAudioSegments: sys,
            userName: "Luis", participants: [Participant(name: "Sarah")]
        )
        XCTAssertEqual(resolutions["SPK_0"], .confirmed("Luis"))
        XCTAssertEqual(resolutions["SPK_1"], .confirmed("Sarah"))
    }

    // MARK: - NoteTabsPresenter two-stream method

    func testNoteTabsPresenter_twoStreamSetSegments_infersSpeakerNames() {
        let p = NoteTabsPresenter()
        let mic = [RawSegment(speaker: "MIC_0", timestamp: 0, text: "Hi from mic")]
        let sys = [RawSegment(speaker: "SYS_0", timestamp: 1, text: "Hi from system")]
        p.setSegments(
            mic: mic, systemAudio: sys,
            userName: "Alice",
            participants: [Participant(name: "Bob")],
            inPerson: false,
            for: "n1"
        )
        let resolutions = p.speakerResolutions(for: "n1")
        XCTAssertEqual(resolutions["MIC_0"], .confirmed("Alice"))
        XCTAssertEqual(resolutions["SYS_0"], .confirmed("Bob"))
    }

    func testNoteTabsPresenter_twoStreamSetSegments_inPerson_micOnly() {
        let p = NoteTabsPresenter()
        let mic = [RawSegment(speaker: "MIC_0", timestamp: 0, text: "In-person speech")]
        let sys = [RawSegment(speaker: "SYS_0", timestamp: 1, text: "System excluded")]
        p.setSegments(mic: mic, systemAudio: sys, inPerson: true, for: "n1")
        if case .segments(let segs) = p.transcriptState(for: "n1") {
            XCTAssertEqual(segs.count, 1)
            XCTAssertEqual(segs[0].text, "In-person speech")
        } else {
            XCTFail("Expected segments")
        }
    }

    func testNoteTabsPresenter_twoStreamSetSegments_firesOnChange() {
        var count = 0
        let p = NoteTabsPresenter()
        p.onChange = { count += 1 }
        p.setSegments(mic: [RawSegment(speaker: "A", timestamp: 0, text: "hi")], systemAudio: [], for: "n1")
        XCTAssertEqual(count, 1)
    }
}
