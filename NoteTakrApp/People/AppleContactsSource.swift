#if canImport(Contacts)
import Contacts
import Foundation
import NoteTakrKit

final class AppleContactsSource: PeopleSource {
    typealias ContactsFetch = ([any CNKeyDescriptor]) throws -> [CNContact]

    static let contactsProviderId = "contacts"

    let providerId = AppleContactsSource.contactsProviderId

    private let authorizationStatus: () -> CNAuthorizationStatus
    private let fetchContacts: ContactsFetch

    convenience init() {
        let store = CNContactStore()
        self.init(
            authorizationStatus: { CNContactStore.authorizationStatus(for: .contacts) },
            fetchContacts: { keys in
                var contacts: [CNContact] = []
                let request = CNContactFetchRequest(keysToFetch: keys)
                request.sortOrder = .userDefault
                try store.enumerateContacts(with: request) { contact, _ in
                    contacts.append(contact)
                }
                return contacts
            }
        )
    }

    init(
        authorizationStatus: @escaping () -> CNAuthorizationStatus,
        fetchContacts: @escaping ContactsFetch
    ) {
        self.authorizationStatus = authorizationStatus
        self.fetchContacts = fetchContacts
    }

    func allPeople() -> [Person] {
        guard authorizationStatus() == .authorized,
              let contacts = try? fetchContacts(Self.keysToFetch) else {
            return []
        }

        return contacts.compactMap(Self.person(from:))
    }

    func search(_ query: String) -> [Person] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return allPeople() }

        return allPeople().filter { person in
            Self.matches(person.name, query: trimmedQuery) ||
                person.emails.contains { Self.matches($0, query: trimmedQuery) }
        }
    }

    private static let keysToFetch: [any CNKeyDescriptor] = [
        CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
        CNContactEmailAddressesKey as CNKeyDescriptor,
        CNContactOrganizationNameKey as CNKeyDescriptor,
    ]

    private static func person(from contact: CNContact) -> Person? {
        let emails = normalizedEmails(contact.emailAddresses.map { String($0.value) })
        guard !emails.isEmpty else { return nil }

        return Person(
            name: displayName(for: contact, fallbackEmail: emails[0]),
            emails: emails
        )
    }

    private static func displayName(for contact: CNContact, fallbackEmail: String) -> String {
        if let fullName = trimmedNonEmpty(CNContactFormatter.string(from: contact, style: .fullName)) {
            return fullName
        }

        if let organization = trimmedNonEmpty(contact.organizationName) {
            return organization
        }

        return inferredName(fromEmail: fallbackEmail) ?? fallbackEmail
    }

    private static func normalizedEmails(_ emails: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        for email in emails {
            let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !normalized.isEmpty, seen.insert(normalized).inserted else { continue }
            result.append(normalized)
        }

        return result
    }

    private static func matches(_ value: String, query: String) -> Bool {
        value.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    private static func trimmedNonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private static func inferredName(fromEmail email: String) -> String? {
        guard let atIndex = email.firstIndex(of: "@") else { return nil }
        let localPart = email[..<atIndex].split(separator: "+", maxSplits: 1).first ?? ""
        let pieces = localPart
            .split { character in
                character == "." || character == "_" || character == "-"
            }
            .map(String.init)
            .filter { !$0.isEmpty }

        guard !pieces.isEmpty else { return nil }
        return pieces.map { $0.localizedCapitalized }.joined(separator: " ")
    }
}
#endif
