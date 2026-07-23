import Foundation

public protocol PeopleSource {
    var providerId: String { get }
    func allPeople() -> [Person]
    func search(_ query: String) -> [Person]
}

extension PastMeetingsIndex: PeopleSource {
    public var providerId: String {
        Self.providerId
    }
}
