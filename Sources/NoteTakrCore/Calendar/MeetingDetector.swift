import Foundation

public struct MeetingScore: Equatable {
    public let event: CalendarEvent
    public let score: Int
    public let detectedVia: DetectionMethod

    public enum DetectionMethod: Equatable {
        case urlMatch(provider: String)
        case keyword(matchedKeyword: String)
    }
}

public struct MeetingDetector {

    private static let urlPatterns: [(String, String)] = [
        ("meet.google.com", "Google Meet"),
        ("zoom.us/j/", "Zoom"),
        ("zoom.us/my/", "Zoom"),
        ("teams.microsoft.com", "Microsoft Teams"),
        ("webex.com", "Cisco Webex"),
        ("gotomeeting.com", "GoTo Meeting"),
    ]

    private static let titleKeywords: [(String, Int)] = [
        ("standup", 3),
        ("stand-up", 3),
        ("stand up", 3),
        ("sync", 2),
        ("call", 2),
        ("meeting", 2),
        ("interview", 3),
        ("1:1", 3),
        ("one-on-one", 3),
        ("one on one", 3),
        ("review", 1),
        ("discussion", 1),
        ("huddle", 2),
        ("demo", 1),
    ]

    public static func score(_ event: CalendarEvent) -> MeetingScore? {
        let candidateURLStrings: [String] = [
            event.url?.absoluteString,
            event.notes,
        ].compactMap { $0 }

        for urlString in candidateURLStrings {
            let lower = urlString.lowercased()
            for (pattern, provider) in urlPatterns where lower.contains(pattern) {
                return MeetingScore(event: event, score: 10, detectedVia: .urlMatch(provider: provider))
            }
        }

        let titleLower = event.title.lowercased()
        let notesLower = event.notes?.lowercased() ?? ""
        var totalScore = 0
        var firstKeyword: String?

        for (keyword, weight) in titleKeywords {
            if titleLower.contains(keyword) {
                if firstKeyword == nil { firstKeyword = keyword }
                totalScore += weight
            } else if notesLower.contains(keyword) {
                if firstKeyword == nil { firstKeyword = keyword }
                totalScore += 1
            }
        }

        guard totalScore > 0, let keyword = firstKeyword else { return nil }
        return MeetingScore(event: event, score: totalScore, detectedVia: .keyword(matchedKeyword: keyword))
    }

    /// Whether an event should be badged as a "meeting" rather than a plain
    /// event. True when it scores via a conferencing URL or meeting keyword, or
    /// when it has at least two attendees (a gathering of people).
    public static func isMeeting(_ event: CalendarEvent) -> Bool {
        if score(event) != nil { return true }
        return event.attendees.count >= 2
    }

    public static func detectMeetings(from events: [CalendarEvent]) -> [MeetingScore] {
        events.compactMap { score($0) }
            .sorted { $0.event.startDate < $1.event.startDate }
    }

    public static func nextMeeting(from events: [CalendarEvent], after date: Date = Date()) -> MeetingScore? {
        detectMeetings(from: events).first { $0.event.startDate >= date }
    }
}
