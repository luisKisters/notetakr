import Foundation
import NoteTakrKit

public enum AccountState: Equatable, Sendable {
    case signedOut
    case signedIn(email: String?)

    public var isSignedIn: Bool {
        if case .signedIn = self {
            return true
        }
        return false
    }

    public var email: String? {
        guard case .signedIn(let email) = self else { return nil }
        return email
    }
}

public enum SummaryUpdateStatus: String, Codable, Equatable, Sendable {
    case ready
    case failed
}

public struct SummaryUpdate: Codable, Equatable, Sendable {
    public var localId: String
    public var text: String
    public var status: SummaryUpdateStatus
    public var message: String?
    public var contentHash: String?
    public var crmPushStatus: CrmPushStatus?

    public init(
        localId: String,
        text: String,
        contentHash: String? = nil,
        crmPushStatus: CrmPushStatus? = nil
    ) {
        self.localId = localId
        self.text = text
        self.status = .ready
        self.message = nil
        self.contentHash = contentHash
        self.crmPushStatus = crmPushStatus
    }

    public init(
        localId: String,
        status: SummaryUpdateStatus,
        text: String = "",
        message: String? = nil,
        contentHash: String? = nil,
        crmPushStatus: CrmPushStatus? = nil
    ) {
        self.localId = localId
        self.text = text
        self.status = status
        self.message = message
        self.contentHash = contentHash
        self.crmPushStatus = crmPushStatus
    }

    enum CodingKeys: String, CodingKey {
        case localId
        case text
        case status
        case message
        case contentHash
        case crmPushStatus
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        localId = try container.decode(String.self, forKey: .localId)
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        status = try container.decodeIfPresent(SummaryUpdateStatus.self, forKey: .status) ?? .ready
        message = try container.decodeIfPresent(String.self, forKey: .message)
        contentHash = try container.decodeIfPresent(String.self, forKey: .contentHash)
        crmPushStatus = try container.decodeIfPresent(CrmPushStatus.self, forKey: .crmPushStatus)
    }
}

public protocol SyncBackend: Sendable {
    var accountState: AccountState { get }

    func upsertMeeting(_ payload: MeetingPayload) async throws
    func accountStateUpdates() -> AsyncStream<AccountState>
    func summaryUpdates() -> AsyncStream<SummaryUpdate>
}

public struct CrmConfiguration: Equatable, Sendable {
    public var provider: String
    public var baseURL: String
    public var apiKey: String

    public init(provider: String = "twenty", baseURL: String, apiKey: String) {
        self.provider = provider
        self.baseURL = baseURL
        self.apiKey = apiKey
    }
}

public enum CrmBackendError: LocalizedError, Equatable, Sendable {
    case configuration(String)
    case unauthorized(String)
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .configuration(let message), .unauthorized(let message), .failed(let message):
            return message
        }
    }
}

public protocol SyncPeopleFetching: Sendable {
    func fetchPeopleSnapshot() async throws -> [ConvexCachedPerson]
}

public protocol CrmSettingsManaging: Sendable {
    func saveCrmConfiguration(_ configuration: CrmConfiguration) async throws
    func testCrmConnection(_ configuration: CrmConfiguration) async throws
    func hasSavedCrmConfiguration() async throws -> Bool
    func refreshCrmPeople() async throws -> [ConvexCachedPerson]
}

public protocol SyncAccountControlling: Sendable {
    var accountState: AccountState { get }

    func signInWithGoogle() async throws
    func signOut() async throws
    func accountStateUpdates() -> AsyncStream<AccountState>
}

public enum MockSyncBackendError: Error, Equatable, Sendable {
    case configuredFailure
}

public final class MockSyncBackend: SyncBackend, SyncPeopleFetching, @unchecked Sendable {
    private let lock = NSLock()
    private let accountStream: AsyncStream<AccountState>
    private let accountContinuation: AsyncStream<AccountState>.Continuation
    private let summaryStream: AsyncStream<SummaryUpdate>
    private let summaryContinuation: AsyncStream<SummaryUpdate>.Continuation

    private var _accountState: AccountState
    private var _failuresBeforeSuccess: Int = 0
    private var _upsertedPayloads: [MeetingPayload] = []
    private var _summarySubscriptionCount: Int = 0
    private var _upsertHandler: (@Sendable (MeetingPayload) async throws -> Void)?
    private var _peopleSnapshot: [ConvexCachedPerson] = []

    public init(accountState: AccountState = .signedOut) {
        _accountState = accountState
        var accountContinuation: AsyncStream<AccountState>.Continuation?
        accountStream = AsyncStream { streamContinuation in
            accountContinuation = streamContinuation
            streamContinuation.yield(accountState)
        }
        self.accountContinuation = accountContinuation!

        var continuation: AsyncStream<SummaryUpdate>.Continuation?
        summaryStream = AsyncStream { streamContinuation in
            continuation = streamContinuation
        }
        summaryContinuation = continuation!
    }

    public var accountState: AccountState {
        get {
            locked { _accountState }
        }
        set {
            locked {
                _accountState = newValue
            }
            accountContinuation.yield(newValue)
        }
    }

    public var failuresBeforeSuccess: Int {
        get {
            locked { _failuresBeforeSuccess }
        }
        set {
            locked {
                _failuresBeforeSuccess = max(0, newValue)
            }
        }
    }

    public var upsertHandler: (@Sendable (MeetingPayload) async throws -> Void)? {
        get {
            locked { _upsertHandler }
        }
        set {
            locked {
                _upsertHandler = newValue
            }
        }
    }

    public var upsertCount: Int {
        locked { _upsertedPayloads.count }
    }

    public var upsertedPayloads: [MeetingPayload] {
        locked { _upsertedPayloads }
    }

    public var summarySubscriptionCount: Int {
        locked { _summarySubscriptionCount }
    }

    public var peopleSnapshot: [ConvexCachedPerson] {
        get {
            locked { _peopleSnapshot }
        }
        set {
            locked {
                _peopleSnapshot = newValue
            }
        }
    }

    public func upsertMeeting(_ payload: MeetingPayload) async throws {
        let result: (handler: (@Sendable (MeetingPayload) async throws -> Void)?, shouldFail: Bool) = locked {
            _upsertedPayloads.append(payload)
            if _failuresBeforeSuccess > 0 {
                _failuresBeforeSuccess -= 1
                return (nil, true)
            }
            return (_upsertHandler, false)
        }

        if result.shouldFail {
            throw MockSyncBackendError.configuredFailure
        }

        guard let handler = result.handler else {
            return
        }
        try await handler(payload)
    }

    public func accountStateUpdates() -> AsyncStream<AccountState> {
        accountStream
    }

    public func summaryUpdates() -> AsyncStream<SummaryUpdate> {
        locked {
            _summarySubscriptionCount += 1
        }
        return summaryStream
    }

    public func emitSummaryUpdate(_ update: SummaryUpdate) {
        summaryContinuation.yield(update)
    }

    public func finishSummaryUpdates() {
        summaryContinuation.finish()
    }

    public func fetchPeopleSnapshot() async throws -> [ConvexCachedPerson] {
        locked { _peopleSnapshot }
    }

    private func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}

extension MockSyncBackend: SyncAccountControlling {
    public func signInWithGoogle() async throws {
        accountState = .signedIn(email: "sync@example.test")
    }

    public func signOut() async throws {
        accountState = .signedOut
    }
}

public enum UnavailableSyncBackendError: LocalizedError, Sendable, Equatable {
    case missingConfiguration([String])

    public var errorDescription: String? {
        switch self {
        case .missingConfiguration(let names):
            return "Missing sync configuration: \(names.joined(separator: ", "))"
        }
    }
}

public final class UnavailableSyncBackend: SyncBackend, SyncAccountControlling, SyncPeopleFetching, CrmSettingsManaging, @unchecked Sendable {
    private let missingConfiguration: [String]

    public init(missingConfiguration: [String]) {
        self.missingConfiguration = missingConfiguration
    }

    public var accountState: AccountState { .signedOut }

    public func signInWithGoogle() async throws {
        throw UnavailableSyncBackendError.missingConfiguration(missingConfiguration)
    }

    public func signOut() async throws {}

    public func upsertMeeting(_ payload: MeetingPayload) async throws {}

    public func fetchPeopleSnapshot() async throws -> [ConvexCachedPerson] {
        []
    }

    public func saveCrmConfiguration(_ configuration: CrmConfiguration) async throws {
        throw UnavailableSyncBackendError.missingConfiguration(missingConfiguration)
    }

    public func testCrmConnection(_ configuration: CrmConfiguration) async throws {
        throw UnavailableSyncBackendError.missingConfiguration(missingConfiguration)
    }

    public func hasSavedCrmConfiguration() async throws -> Bool {
        false
    }

    public func refreshCrmPeople() async throws -> [ConvexCachedPerson] {
        []
    }

    public func accountStateUpdates() -> AsyncStream<AccountState> {
        AsyncStream { continuation in
            continuation.yield(.signedOut)
            continuation.finish()
        }
    }

    public func summaryUpdates() -> AsyncStream<SummaryUpdate> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }
}
