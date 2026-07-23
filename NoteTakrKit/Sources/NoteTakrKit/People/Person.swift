import Foundation

public struct SourceRef: Equatable, Hashable, Codable, Sendable {
    public var provider: String
    public var remoteId: String

    public init(provider: String, remoteId: String) {
        self.provider = provider
        self.remoteId = remoteId
    }
}

public struct Person: Equatable, Hashable, Codable, Sendable {
    public var name: String
    public var emails: [String]
    public var company: String?
    public var sourceRefs: [SourceRef]

    public init(
        name: String,
        emails: [String] = [],
        company: String? = nil,
        sourceRefs: [SourceRef] = []
    ) {
        let normalizedEmails = Self.normalizedEmails(emails)
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.emails = normalizedEmails
        self.company = Self.trimmedNonEmpty(company) ?? Self.derivedCompany(from: normalizedEmails.first)
        self.sourceRefs = Self.deduplicatedSourceRefs(sourceRefs)
    }

    public static func normalizedEmail(_ email: String?) -> String? {
        let trimmed = email?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    static func matches(_ text: String, query: String) -> Bool {
        text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    private static func normalizedEmails(_ emails: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        for email in emails {
            guard let normalized = normalizedEmail(email), !seen.contains(normalized) else { continue }
            seen.insert(normalized)
            result.append(normalized)
        }

        return result
    }

    private static func deduplicatedSourceRefs(_ refs: [SourceRef]) -> [SourceRef] {
        var seen = Set<SourceRef>()
        var result: [SourceRef] = []

        for ref in refs {
            guard !seen.contains(ref) else { continue }
            seen.insert(ref)
            result.append(ref)
        }

        return result
    }

    private static func derivedCompany(from email: String?) -> String? {
        guard let email, let atIndex = email.firstIndex(of: "@") else { return nil }
        let domain = String(email[email.index(after: atIndex)...]).lowercased()
        guard !publicEmailDomains.contains(domain) else { return nil }

        let labels = domain.split(separator: ".").map(String.init)
        guard labels.count >= 2, let secondLevel = labels.dropLast().last, !secondLevel.isEmpty else {
            return nil
        }

        return titleCasedCompanyLabel(secondLevel)
    }

    private static func titleCasedCompanyLabel(_ label: String) -> String {
        label
            .split { character in
                character == "-" || character == "_"
            }
            .map { piece in
                let lower = piece.lowercased()
                guard let first = lower.first else { return "" }
                return first.uppercased() + lower.dropFirst()
            }
            .joined(separator: " ")
    }

    private static func trimmedNonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private static let publicEmailDomains: Set<String> = [
        "aol.com",
        "fastmail.com",
        "gmail.com",
        "googlemail.com",
        "hey.com",
        "hotmail.com",
        "icloud.com",
        "live.com",
        "me.com",
        "msn.com",
        "outlook.com",
        "pm.me",
        "proton.me",
        "protonmail.com",
        "yahoo.com",
    ]
}
