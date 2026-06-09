import Foundation

/// A meeting participant, sourced from a linked calendar event's attendees.
/// `email` is best-effort — some calendar accounts expose only a display name.
public struct Participant: Codable, Identifiable, Equatable, Sendable {
    public var name: String
    public var email: String?

    /// Stable identity for SwiftUI lists and de-duplication: the email when known,
    /// otherwise the name. Computed, so it is excluded from the Codable form.
    public var id: String { email ?? name }

    public init(name: String, email: String? = nil) {
        self.name = name
        self.email = email
    }
}
