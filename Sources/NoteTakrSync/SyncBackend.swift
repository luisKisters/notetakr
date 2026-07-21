import Foundation

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

public struct SummaryUpdate: Codable, Equatable, Sendable {
    public var localId: String
    public var text: String

    public init(localId: String, text: String) {
        self.localId = localId
        self.text = text
    }
}

public protocol SyncBackend: Sendable {
    var accountState: AccountState { get }

    func upsertMeeting(_ payload: MeetingPayload) async throws
    func accountStateUpdates() -> AsyncStream<AccountState>
    func summaryUpdates() -> AsyncStream<SummaryUpdate>
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

public final class MockSyncBackend: SyncBackend, @unchecked Sendable {
    private let lock = NSLock()
    private let accountStream: AsyncStream<AccountState>
    private let accountContinuation: AsyncStream<AccountState>.Continuation
    private let summaryStream: AsyncStream<SummaryUpdate>
    private let summaryContinuation: AsyncStream<SummaryUpdate>.Continuation

    private var _accountState: AccountState
    private var _failuresBeforeSuccess: Int = 0
    private var _upsertedPayloads: [MeetingPayload] = []
    private var _upsertHandler: (@Sendable (MeetingPayload) async throws -> Void)?

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
        summaryStream
    }

    public func emitSummaryUpdate(_ update: SummaryUpdate) {
        summaryContinuation.yield(update)
    }

    public func finishSummaryUpdates() {
        summaryContinuation.finish()
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

public final class UnavailableSyncBackend: SyncBackend, SyncAccountControlling, @unchecked Sendable {
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
