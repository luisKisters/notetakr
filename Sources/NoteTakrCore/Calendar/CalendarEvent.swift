import Foundation

public struct CalendarEvent: Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let startDate: Date
    public let endDate: Date
    public let url: URL?
    public let notes: String?
    public let attendees: [Participant]
    public let organizerEmail: String?

    public init(
        id: String,
        title: String,
        startDate: Date,
        endDate: Date,
        url: URL? = nil,
        notes: String? = nil,
        attendees: [Participant] = [],
        organizerEmail: String? = nil
    ) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.url = url
        self.notes = notes
        self.attendees = attendees
        self.organizerEmail = organizerEmail
    }
}
