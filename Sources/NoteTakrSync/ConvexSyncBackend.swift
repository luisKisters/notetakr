import Foundation
import NoteTakrKit

public struct ConvexSyncConfiguration: Equatable, Sendable {
    public var deploymentURL: String
    public var clerkPublishableKey: String
    public var callbackURLScheme: String?

    public init(
        deploymentURL: String,
        clerkPublishableKey: String,
        callbackURLScheme: String? = nil
    ) {
        self.deploymentURL = deploymentURL
        self.clerkPublishableKey = clerkPublishableKey
        self.callbackURLScheme = callbackURLScheme
    }
}

public enum ConvexSyncBackendError: LocalizedError, Sendable, Equatable {
    case sdkUnavailable
    case signInFailed(String)

    public var errorDescription: String? {
        switch self {
        case .sdkUnavailable:
            return "Clerk/Convex Swift SDKs are unavailable on this platform."
        case .signInFailed(let message):
            return message
        }
    }
}

#if canImport(ClerkKit) && canImport(ClerkConvex) && canImport(ConvexMobile)
import Combine
import ClerkKit
import ClerkConvex
@preconcurrency import ConvexMobile

public final class ConvexSyncBackend: SyncBackend, SyncAccountControlling, SyncPeopleFetching, CrmSettingsManaging, @unchecked Sendable {
    private let client: ConvexClientWithAuth<String>
    private let lock = NSLock()
    private var cancellables = Set<AnyCancellable>()
    private var _accountState: AccountState = .signedOut
    private let accountStream: AsyncStream<AccountState>
    private let accountContinuation: AsyncStream<AccountState>.Continuation

    @MainActor
    public init(configuration: ConvexSyncConfiguration) {
        let options: Clerk.Options
        if let callbackURLScheme = configuration.callbackURLScheme,
           !callbackURLScheme.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            options = Clerk.Options(
                redirectConfig: .init(
                    redirectUrl: "\(callbackURLScheme)://callback",
                    callbackUrlScheme: callbackURLScheme
                )
            )
        } else {
            options = Clerk.Options()
        }
        Clerk.configure(publishableKey: configuration.clerkPublishableKey, options: options)

        let authProvider = ClerkConvexAuthProvider()
        client = ConvexClientWithAuth(
            deploymentUrl: configuration.deploymentURL,
            authProvider: authProvider
        )

        var continuation: AsyncStream<AccountState>.Continuation?
        accountStream = AsyncStream { streamContinuation in
            continuation = streamContinuation
            streamContinuation.yield(.signedOut)
        }
        accountContinuation = continuation!

        observeAuthState()
        Task {
            _ = await client.loginFromCache()
            await refreshAccountStateFromClerk()
        }
    }

    public var accountState: AccountState {
        locked { _accountState }
    }

    public func signInWithGoogle() async throws {
        do {
            try await signInWithGoogleOnMainActor()
            _ = await client.loginFromCache()
            await refreshAccountStateFromClerk()
        } catch {
            setAccountState(.signedOut)
            throw ConvexSyncBackendError.signInFailed(error.localizedDescription)
        }
    }

    public func signOut() async throws {
        await client.logout()
        try await signOutOnMainActor()
        setAccountState(.signedOut)
    }

    public func upsertMeeting(_ payload: MeetingPayload) async throws {
        let _: UpsertResult = try await client.mutation(
            "meetings:upsertFromDevice",
            with: ["payload": convexPayload(payload)]
        )
    }

    public func fetchPeopleSnapshot() async throws -> [ConvexCachedPerson] {
        try await client.action("crm/mirror:fetchCurrentPeopleSnapshot")
    }

    public func saveCrmConfiguration(_ configuration: CrmConfiguration) async throws {
        let _: SaveCrmConfigResult = try await client.action(
            "crm/mirror:saveCrmConfig",
            with: ["crm": convexCrmConfiguration(configuration)]
        )
    }

    public func testCrmConnection(_ configuration: CrmConfiguration) async throws {
        let result: CrmConnectionResult = try await client.action(
            "crm/mirror:testCrmConnection",
            with: ["crm": convexCrmConfiguration(configuration)]
        )
        guard result.ok else {
            throw Self.crmBackendError(from: result)
        }
    }

    public func hasSavedCrmConfiguration() async throws -> Bool {
        let result: CrmConnectionStateResult = try await client.action(
            "crm/mirror:crmConnectionState"
        )
        return result.connected
    }

    public func accountStateUpdates() -> AsyncStream<AccountState> {
        accountStream
    }

    public func summaryUpdates() -> AsyncStream<SummaryUpdate> {
        AsyncStream { continuation in
            let lock = NSLock()
            var seen: [String: String] = [:]
            let cancellable = client
                .subscribe(to: "meetings:summaryUpdates", yielding: [ReadySummary].self)
                .sink(
                    receiveCompletion: { _ in },
                    receiveValue: { rows in
                        for row in rows {
                            let status = SummaryUpdateStatus(rawValue: row.summaryStatus ?? "ready") ?? .ready
                            let summary = row.summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                            guard status == .failed || !summary.isEmpty else { continue }
                            let crmPushStatus = row.pushStatus.flatMap(CrmPushStatus.init(rawValue:))
                            let message = row.summaryError?.trimmingCharacters(in: .whitespacesAndNewlines)
                            let seenValue = "\(status.rawValue)\n\(summary)\n\(message ?? "")\n\(row.contentHash)\n\(row.pushStatus ?? "")"
                            let shouldYield: Bool = {
                                lock.lock()
                                defer { lock.unlock() }
                                guard seen[row.localId] != seenValue else { return false }
                                seen[row.localId] = seenValue
                                return true
                            }()
                            if shouldYield {
                                continuation.yield(
                                    SummaryUpdate(
                                        localId: row.localId,
                                        status: status,
                                        text: summary,
                                        message: message?.isEmpty == false ? message : nil,
                                        contentHash: row.contentHash,
                                        crmPushStatus: crmPushStatus
                                    )
                                )
                            }
                        }
                    }
                )
            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }

    private func observeAuthState() {
        client.authState
            .sink { [weak self] state in
                guard let self else { return }
                Task {
                    switch state {
                    case .authenticated(_):
                        await self.refreshAccountStateFromClerk()
                    case .unauthenticated:
                        self.setAccountState(.signedOut)
                    case .loading:
                        break
                    }
                }
            }
            .store(in: &cancellables)
    }

    @MainActor
    private func signInWithGoogleOnMainActor() async throws {
        _ = try await Clerk.shared.auth.signInWithOAuth(provider: .google)
    }

    @MainActor
    private func signOutOnMainActor() async throws {
        try await Clerk.shared.auth.signOut()
    }

    @MainActor
    private func currentClerkAccountState() -> AccountState {
        guard Clerk.shared.session?.status == .active else {
            return .signedOut
        }
        let email = Clerk.shared.user?.primaryEmailAddress?.emailAddress
            ?? Clerk.shared.user?.emailAddresses.first?.emailAddress
        return .signedIn(email: email)
    }

    private func refreshAccountStateFromClerk() async {
        let state = await currentClerkAccountState()
        setAccountState(state)
    }

    private func setAccountState(_ state: AccountState) {
        locked {
            _accountState = state
        }
        accountContinuation.yield(state)
    }

    private func convexPayload(_ payload: MeetingPayload) -> [String: ConvexEncodable?] {
        [
            "localId": payload.localId,
            "title": payload.title,
            "startedAt": Self.iso8601.string(from: payload.startedAt),
            "calendarEventId": payload.calendarEventId,
            "participants": payload.participants.map { participant -> ConvexEncodable? in
                [
                    "name": participant.name,
                    "email": participant.email,
                    "crm": participant.crm,
                ] as [String: ConvexEncodable?]
            },
            "markdownBody": payload.markdownBody,
            "transcriptSegments": payload.transcriptSegments.map { segment -> ConvexEncodable? in
                [
                    "seq": segment.seq,
                    "startMs": segment.startMs,
                    "speaker": segment.speaker,
                    "text": segment.text,
                ] as [String: ConvexEncodable?]
            },
            "crmPushOptOut": payload.crmPushOptOut,
            "contentHash": payload.contentHash,
        ]
    }

    private func convexCrmConfiguration(_ configuration: CrmConfiguration) -> [String: ConvexEncodable?] {
        [
            "provider": configuration.provider,
            "baseUrl": configuration.baseURL,
            "apiKey": configuration.apiKey,
        ]
    }

    private static func crmBackendError(from result: CrmConnectionResult) -> CrmBackendError {
        let message = result.message?.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = message?.isEmpty == false ? message! : "CRM connection failed"
        switch result.code {
        case "unauthorized":
            return .unauthorized(fallback)
        case "configuration":
            return .configuration(fallback)
        default:
            return .failed(fallback)
        }
    }

    private func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    private static let iso8601 = ISO8601DateFormatter()

    private struct UpsertResult: Decodable {
        var scheduledSummary: Bool
    }

    private struct SaveCrmConfigResult: Decodable {
        var scheduledMirror: Bool
    }

    private struct CrmConnectionResult: Decodable {
        var ok: Bool
        var code: String?
        var message: String?
    }

    private struct CrmConnectionStateResult: Decodable {
        var connected: Bool
        var provider: String?
    }

    private struct ReadySummary: Decodable {
        var localId: String
        var contentHash: String
        var summary: String?
        var summaryStatus: String?
        var summaryError: String?
        var pushStatus: String?
    }
}
#else
public final class ConvexSyncBackend: SyncBackend, SyncAccountControlling, SyncPeopleFetching, CrmSettingsManaging, @unchecked Sendable {
    public init(configuration: ConvexSyncConfiguration) throws {
        throw ConvexSyncBackendError.sdkUnavailable
    }

    public var accountState: AccountState { .signedOut }

    public func signInWithGoogle() async throws {
        throw ConvexSyncBackendError.sdkUnavailable
    }

    public func signOut() async throws {}

    public func upsertMeeting(_ payload: MeetingPayload) async throws {
        throw ConvexSyncBackendError.sdkUnavailable
    }

    public func fetchPeopleSnapshot() async throws -> [ConvexCachedPerson] {
        throw ConvexSyncBackendError.sdkUnavailable
    }

    public func saveCrmConfiguration(_ configuration: CrmConfiguration) async throws {
        throw ConvexSyncBackendError.sdkUnavailable
    }

    public func testCrmConnection(_ configuration: CrmConfiguration) async throws {
        throw ConvexSyncBackendError.sdkUnavailable
    }

    public func hasSavedCrmConfiguration() async throws -> Bool {
        throw ConvexSyncBackendError.sdkUnavailable
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
#endif
