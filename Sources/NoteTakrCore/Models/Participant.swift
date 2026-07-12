import Foundation

/// A meeting participant, sourced from a linked calendar event's attendees.
/// `email` is best-effort — some calendar accounts expose only a display name.
public struct Participant: Codable, Identifiable, Equatable, Sendable {
    public var name: String
    public var email: String?
    public var crm: String?

    /// Stable identity for SwiftUI lists and de-duplication: CRM link, email, or name.
    /// Computed, so it is excluded from the Codable form.
    public var id: String { crm ?? email ?? name }

    public init(name: String, email: String? = nil, crm: String? = nil) {
        self.name = name
        self.email = email
        self.crm = crm
    }
}
