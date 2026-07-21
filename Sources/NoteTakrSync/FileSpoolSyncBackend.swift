import Foundation

public final class FileSpoolSyncBackend: SyncBackend, SyncAccountControlling, @unchecked Sendable {
    public let rootURL: URL
    public let payloadsURL: URL
    public let summariesURL: URL

    private let pollInterval: TimeInterval
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let lock = NSLock()
    private var _accountState: AccountState
    private let accountStream: AsyncStream<AccountState>
    private let accountContinuation: AsyncStream<AccountState>.Continuation

    public init(
        rootURL: URL,
        accountEmail: String? = "e2e-sync@example.test",
        pollInterval: TimeInterval = 0.1
    ) {
        self.rootURL = rootURL
        self.payloadsURL = rootURL.appendingPathComponent("Payloads", isDirectory: true)
        self.summariesURL = rootURL.appendingPathComponent("Summaries", isDirectory: true)
        self.pollInterval = pollInterval
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let state = AccountState.signedIn(email: accountEmail)
        self._accountState = state
        var continuation: AsyncStream<AccountState>.Continuation?
        self.accountStream = AsyncStream { streamContinuation in
            continuation = streamContinuation
            streamContinuation.yield(state)
        }
        self.accountContinuation = continuation!
    }

    public var accountState: AccountState {
        locked { _accountState }
    }

    public func signInWithGoogle() async throws {
        setAccountState(.signedIn(email: accountState.email ?? "e2e-sync@example.test"))
    }

    public func signOut() async throws {
        setAccountState(.signedOut)
    }

    public func upsertMeeting(_ payload: MeetingPayload) async throws {
        try FileManager.default.createDirectory(at: payloadsURL, withIntermediateDirectories: true)
        let data = try encoder.encode(payload)
        try data.write(to: payloadURL(for: payload.localId), options: .atomic)
    }

    public func accountStateUpdates() -> AsyncStream<AccountState> {
        accountStream
    }

    public func summaryUpdates() -> AsyncStream<SummaryUpdate> {
        AsyncStream { continuation in
            let task = Task {
                var seen = Set<String>()
                while !Task.isCancelled {
                    do {
                        for update in try pendingSummaryUpdates(seen: &seen) {
                            continuation.yield(update)
                        }
                    } catch {
                        // The DEBUG e2e seam should stay deterministic and non-fatal:
                        // malformed files are ignored until the test rewrites them.
                    }

                    let nanoseconds = UInt64(max(0.01, pollInterval) * 1_000_000_000)
                    try? await Task.sleep(nanoseconds: nanoseconds)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func payloadURL(for localId: String) -> URL {
        payloadsURL.appendingPathComponent("\(localId).json")
    }

    public func summaryURL(for localId: String) -> URL {
        summariesURL.appendingPathComponent("\(localId).json")
    }

    private func setAccountState(_ state: AccountState) {
        locked {
            _accountState = state
        }
        accountContinuation.yield(state)
    }

    private func pendingSummaryUpdates(seen: inout Set<String>) throws -> [SummaryUpdate] {
        guard FileManager.default.fileExists(atPath: summariesURL.path) else { return [] }
        let files = try FileManager.default.contentsOfDirectory(
            at: summariesURL,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        )
        var updates: [SummaryUpdate] = []
        for file in files where file.pathExtension == "json" {
            let key = file.lastPathComponent
            guard !seen.contains(key) else { continue }
            let data = try Data(contentsOf: file)
            let update = try decoder.decode(SummaryUpdate.self, from: data)
            seen.insert(key)
            updates.append(update)
        }
        return updates
    }

    private func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}
