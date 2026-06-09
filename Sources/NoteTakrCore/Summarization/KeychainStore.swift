import Foundation

/// Stores a single secret (the OpenRouter API key) in the macOS Keychain so it is
/// never written to disk in plaintext. The `#if canImport(Security)` guard keeps
/// the type usable on platforms without the Security framework (no-op fallback).
#if canImport(Security)
import Security

public struct KeychainStore: Sendable {
    public let service: String
    public let account: String

    public init(service: String = "com.notetakr.openrouter", account: String = "api-key") {
        self.service = service
        self.account = account
    }

    public func save(_ value: String) throws {
        let data = Data(value.utf8)
        // Replace any existing item so this is an upsert.
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unhandled(status)
        }
    }

    public func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty
        else {
            return nil
        }
        return value
    }

    public func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    public var hasValue: Bool { read() != nil }

    public enum KeychainError: Error, Equatable {
        case unhandled(OSStatus)
    }
}
#else
public struct KeychainStore: Sendable {
    public init(service: String = "com.notetakr.openrouter", account: String = "api-key") {}
    public func save(_ value: String) throws {}
    public func read() -> String? { nil }
    public func delete() {}
    public var hasValue: Bool { false }
}
#endif
