import Foundation

public struct CrmStatusPresenter: Equatable {
    public private(set) var dismissedMeetingIds: Set<String>

    public init(dismissedMeetingIds: Set<String> = []) {
        self.dismissedMeetingIds = dismissedMeetingIds
    }

    public func bannerText(
        meetingId: String,
        crmConnected: Bool,
        unmatchedParticipants: [Participant]
    ) -> String? {
        guard crmConnected,
              !dismissedMeetingIds.contains(meetingId),
              !unmatchedParticipants.isEmpty else {
            return nil
        }

        let count = unmatchedParticipants.count
        return count == 1 ? "1 participant not in CRM" : "\(count) participants not in CRM"
    }

    public mutating func dismiss(meetingId: String) {
        dismissedMeetingIds.insert(meetingId)
    }
}
