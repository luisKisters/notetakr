import Foundation

/// Applies conservative, user-facing names after diarization has separated voices.
///
/// A microphone-only recording can contain everyone in the room, so a speaker is
/// only treated as a meaningful additional in-room voice after more than
/// `inRoomWordThreshold` words. When several voices clear that threshold, names
/// are intentionally withheld rather than guessing who is who.
public struct SpeakerLabelResolver {
    public static let inRoomWordThreshold = 50
    public static let inRoomSpeakerPrefix = "In-room speaker "

    public static func resolve(
        segments: [TranscriptSegment],
        session: MeetingSession,
        userName: String?,
        inferNamesFromCalendar: Bool,
        inRoomWordThreshold: Int = SpeakerLabelResolver.inRoomWordThreshold
    ) -> [TranscriptSegment] {
        guard !segments.isEmpty else { return [] }

        let trimmedUserName = trimmedNonEmpty(userName)
        let counts = wordCounts(in: segments)

        if session.inPerson {
            return resolveInRoom(
                segments: segments,
                counts: counts,
                session: session,
                userName: trimmedUserName,
                inferNamesFromCalendar: inferNamesFromCalendar,
                threshold: inRoomWordThreshold
            )
        }

        return resolveRemote(
            segments: segments,
            counts: counts,
            session: session,
            userName: trimmedUserName,
            inferNamesFromCalendar: inferNamesFromCalendar,
            threshold: inRoomWordThreshold
        )
    }

    public static func hasMultipleInRoomSpeakers(_ segments: [TranscriptSegment]) -> Bool {
        let speakers: [String] = segments.compactMap { segment in
            guard let speaker = segment.speaker,
                  speaker.hasPrefix(inRoomSpeakerPrefix) else { return nil }
            return speaker
        }
        return Set(speakers).count > 1
    }

    private static func resolveInRoom(
        segments: [TranscriptSegment],
        counts: [String: Int],
        session: MeetingSession,
        userName: String?,
        inferNamesFromCalendar: Bool,
        threshold: Int
    ) -> [TranscriptSegment] {
        let orderedSpeakers = speakersByFirstAppearance(in: segments)
        guard !orderedSpeakers.isEmpty else { return segments }

        let meaningfulSpeakers = orderedSpeakers.filter { counts[$0, default: 0] > threshold }
        if meaningfulSpeakers.count > 1 {
            let names = Dictionary(uniqueKeysWithValues: orderedSpeakers.enumerated().map {
                ($0.element, "\(inRoomSpeakerPrefix)\($0.offset + 1)")
            })
            return renaming(segments, with: names)
        }

        // A short interjection (50 words or fewer) does not make the recording a
        // multi-person room for naming purposes. Name only the dominant voice;
        // brief, separately diarized voices keep their neutral speaker labels.
        let dominant = meaningfulSpeakers.first ?? orderedSpeakers.max {
            counts[$0, default: 0] < counts[$1, default: 0]
        }
        guard let dominant else { return segments }

        let calendarName = inferNamesFromCalendar
            ? soleOtherParticipant(in: session.participants, userName: userName)?.name
            : nil
        let resolvedName = trimmedNonEmpty(calendarName) ?? userName.map { "\($0) (You)" }
        guard let resolvedName else { return segments }
        return renaming(segments, with: [dominant: resolvedName])
    }

    private static func resolveRemote(
        segments: [TranscriptSegment],
        counts: [String: Int],
        session: MeetingSession,
        userName: String?,
        inferNamesFromCalendar: Bool,
        threshold: Int
    ) -> [TranscriptSegment] {
        let orderedSpeakers = speakersByFirstAppearance(in: segments)
        guard !orderedSpeakers.isEmpty else { return segments }

        var names: [String: String] = [:]
        let microphoneSpeaker = orderedSpeakers.first(where: isMicrophoneSpeaker)
        if let microphoneSpeaker, let userName {
            names[microphoneSpeaker] = "\(userName) (You)"
        }

        guard inferNamesFromCalendar,
              let otherName = soleOtherParticipant(in: session.participants, userName: userName)?.name,
              let resolvedOtherName = trimmedNonEmpty(otherName)
        else {
            return renaming(segments, with: names)
        }

        let otherSpeakers = orderedSpeakers.filter { $0 != microphoneSpeaker }
        let meaningfulOthers = otherSpeakers.filter { counts[$0, default: 0] > threshold }
        let soleOtherSpeaker: String?
        if meaningfulOthers.count == 1 {
            soleOtherSpeaker = meaningfulOthers[0]
        } else if meaningfulOthers.isEmpty, otherSpeakers.count == 1 {
            soleOtherSpeaker = otherSpeakers[0]
        } else {
            soleOtherSpeaker = nil
        }
        if let soleOtherSpeaker {
            names[soleOtherSpeaker] = resolvedOtherName
        }
        return renaming(segments, with: names)
    }

    private static func wordCounts(in segments: [TranscriptSegment]) -> [String: Int] {
        var result: [String: Int] = [:]
        for segment in segments {
            guard let speaker = segment.speaker else { continue }
            result[speaker, default: 0] += segment.text.split { $0.isWhitespace }.count
        }
        return result
    }

    private static func speakersByFirstAppearance(in segments: [TranscriptSegment]) -> [String] {
        var seen = Set<String>()
        return segments.compactMap { segment in
            guard let speaker = segment.speaker, seen.insert(speaker).inserted else { return nil }
            return speaker
        }
    }

    private static func isMicrophoneSpeaker(_ speaker: String) -> Bool {
        speaker == "Speaker 1 (You)" || speaker.hasSuffix(" (You)")
    }

    private static func soleOtherParticipant(
        in participants: [Participant],
        userName: String?
    ) -> Participant? {
        let candidates: [Participant]
        if let userName {
            candidates = participants.filter {
                !namesReferToSamePerson($0.name, userName)
            }
        } else {
            candidates = participants
        }
        return candidates.count == 1 ? candidates[0] : nil
    }

    private static func namesReferToSamePerson(_ lhs: String, _ rhs: String) -> Bool {
        let left = lhs.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let right = rhs.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !left.isEmpty, !right.isEmpty else { return false }
        return left == right
            || left.hasPrefix(right + " ")
            || right.hasPrefix(left + " ")
    }

    private static func renaming(
        _ segments: [TranscriptSegment],
        with names: [String: String]
    ) -> [TranscriptSegment] {
        guard !names.isEmpty else { return segments }
        return segments.map { segment in
            guard let speaker = segment.speaker, let name = names[speaker] else { return segment }
            var renamed = segment
            renamed.speaker = name
            return renamed
        }
    }

    private static func trimmedNonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}
