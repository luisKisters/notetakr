#if canImport(EventKit)
import Contacts
import EventKit
import NoteTakrCore

protocol ContactNameResolving {
    /// Returns a Contacts display name only when the user has authorized access.
    /// A nil result tells callers to preserve their non-Contacts fallback.
    func displayName(forEmail email: String) -> String?
}

/// Privacy-gated, read-only lookup of contact names by attendee email address.
///
/// This type never requests access. Permission is requested only from the explicit
/// Contacts row in Settings; calendar loading merely uses access already granted.
final class ContactNameResolver: ContactNameResolving {
    typealias ContactLookup = (NSPredicate, [any CNKeyDescriptor]) throws -> [CNContact]

    private let authorizationStatus: () -> CNAuthorizationStatus
    private let contactLookup: ContactLookup

    init(store: CNContactStore = CNContactStore()) {
        authorizationStatus = { CNContactStore.authorizationStatus(for: .contacts) }
        contactLookup = { predicate, keys in
            try store.unifiedContacts(matching: predicate, keysToFetch: keys)
        }
    }

    /// Dependency-injected initializer for permission and fallback regression tests.
    init(
        authorizationStatus: @escaping () -> CNAuthorizationStatus,
        contactLookup: @escaping ContactLookup
    ) {
        self.authorizationStatus = authorizationStatus
        self.contactLookup = contactLookup
    }

    func displayName(forEmail email: String) -> String? {
        // Do not touch CNContactStore unless the user has explicitly granted access.
        guard authorizationStatus() == .authorized else { return nil }

        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedEmail.isEmpty else { return nil }

        let predicate = CNContact.predicateForContacts(matchingEmailAddress: normalizedEmail)
        let keys: [any CNKeyDescriptor] = [
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName)
        ]
        guard let contacts = try? contactLookup(predicate, keys) else { return nil }

        return contacts.lazy.compactMap { contact in
            CNContactFormatter.string(from: contact, style: .fullName)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }.first(where: { !$0.isEmpty })
    }
}

public final class EventKitCalendarAdapter: CalendarAdapter {
    private let store = EKEventStore()
    private let contactNameResolver: any ContactNameResolving

    public convenience init() {
        self.init(contactNameResolver: ContactNameResolver())
    }

    init(contactNameResolver: any ContactNameResolving) {
        self.contactNameResolver = contactNameResolver
    }

    public var hasAccess: Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        if #available(macOS 14.0, *) {
            // .limited is iOS-only; on macOS only fullAccess grants calendar reads
            return status == .fullAccess
        } else {
            return status == .authorized
        }
    }

    public func requestAccess() async throws {
        let granted: Bool
        if #available(macOS 14.0, *) {
            granted = try await store.requestFullAccessToEvents()
        } else {
            granted = await withCheckedContinuation { continuation in
                store.requestAccess(to: .event) { result, _ in
                    continuation.resume(returning: result)
                }
            }
        }
        guard granted else { throw CalendarError.accessDenied }
    }

    public func fetchUpcomingEvents(from: Date, to: Date) async throws -> [CalendarEvent] {
        let predicate = store.predicateForEvents(withStart: from, end: to, calendars: nil)
        return store.events(matching: predicate).map {
            CalendarEvent(ekEvent: $0, contactNameResolver: contactNameResolver)
        }
    }
}

private extension CalendarEvent {
    init(ekEvent: EKEvent, contactNameResolver: any ContactNameResolving) {
        self.init(
            id: Self.occurrenceID(for: ekEvent),
            title: ekEvent.title ?? "Untitled",
            startDate: ekEvent.startDate ?? Date(),
            endDate: ekEvent.endDate ?? Date(),
            location: ekEvent.location,
            url: ekEvent.url,
            notes: ekEvent.notes,
            attendees: (ekEvent.attendees ?? []).map {
                Participant(ekParticipant: $0, contactNameResolver: contactNameResolver)
            },
            organizerEmail: ekEvent.organizer.flatMap { Participant.email(from: $0) }
        )
    }

    /// EventKit reuses one `eventIdentifier` across every occurrence of a
    /// recurring event. Append the occurrence start so each occurrence has a
    /// stable, unique id (safe for SwiftUI lists and for linking to a session).
    static func occurrenceID(for ekEvent: EKEvent) -> String {
        let base = ekEvent.eventIdentifier ?? UUID().uuidString
        guard let start = ekEvent.startDate else { return base }
        return "\(base)@\(Int(start.timeIntervalSince1970))"
    }
}

extension Participant {
    init(ekParticipant: EKParticipant, contactNameResolver: any ContactNameResolving) {
        let email = Participant.email(from: ekParticipant)
        self.init(
            name: Participant.resolvedDisplayName(
                calendarName: ekParticipant.name,
                email: email,
                contactNameResolver: contactNameResolver
            ),
            email: email
        )
    }

    static func resolvedDisplayName(
        calendarName: String?,
        email: String?,
        contactNameResolver: any ContactNameResolving
    ) -> String {
        email.flatMap(contactNameResolver.displayName(forEmail:))
            ?? displayName(name: calendarName, email: email)
    }

    /// Attendee emails are best-effort: EventKit exposes them via the participant's
    /// `mailto:` URL, and some accounts expose a name only.
    static func email(from participant: EKParticipant) -> String? {
        let components = URLComponents(url: participant.url, resolvingAgainstBaseURL: false)
        guard components?.scheme?.lowercased() == "mailto" else { return nil }
        let path = components?.path ?? ""
        return path.isEmpty ? nil : path
    }

    static func displayName(name: String?, email: String?) -> String {
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = email?.trimmingCharacters(in: .whitespacesAndNewlines)

        if let trimmedName,
           !trimmedName.isEmpty,
           trimmedName.caseInsensitiveCompare(trimmedEmail ?? "") != .orderedSame {
            return trimmedName
        }

        if let trimmedEmail,
           let inferred = inferredName(fromEmail: trimmedEmail) {
            return inferred
        }

        return trimmedName?.isEmpty == false ? trimmedName! : "Unknown"
    }

    static func inferredName(fromEmail email: String) -> String? {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let atIndex = trimmed.firstIndex(of: "@") else { return nil }
        let localPart = trimmed[..<atIndex].split(separator: "+", maxSplits: 1).first ?? ""
        let pieces = localPart
            .split { character in
                character == "." || character == "_" || character == "-"
            }
            .map(String.init)
            .filter { !$0.isEmpty }

        guard !pieces.isEmpty else { return nil }
        return pieces
            .map { $0.localizedCapitalized }
            .joined(separator: " ")
    }
}
#endif
