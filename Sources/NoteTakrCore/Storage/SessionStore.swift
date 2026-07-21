import Foundation

public final class SessionStore: @unchecked Sendable {
    public let baseURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(baseURL: URL) {
        self.baseURL = baseURL
        encoder = JSONEncoder()
        decoder = JSONDecoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    public static func sanitizeTitle(_ title: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ "))
        let filtered = title.unicodeScalars
            .filter { allowed.contains($0) }
            .map { String($0) }
            .joined()
        var result = filtered.trimmingCharacters(in: .whitespaces)
        // Collapse multiple spaces before converting to dashes
        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }
        result = result.replacingOccurrences(of: " ", with: "-")
        return result.isEmpty ? "unnamed" : String(result.prefix(64))
    }

    public static func folderName(for session: MeetingSession) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        let dateStr = formatter.string(from: session.date)
        let titleSlug = sanitizeTitle(session.title)
        let shortID = String(session.id.uuidString.prefix(8))
        return "\(dateStr)_\(titleSlug)_\(shortID)"
    }

    public func sessionURL(for session: MeetingSession) -> URL {
        baseURL.appendingPathComponent(Self.folderName(for: session), isDirectory: true)
    }

    public func save(_ session: MeetingSession) throws {
        var session = session
        let targetDir = sessionURL(for: session)
        // If the session title was renamed the folder name changes. Find any existing
        // folder for this session ID and move it to the new path so audio files are
        // not orphaned.
        let shortID = String(session.id.uuidString.prefix(8))
        if FileManager.default.fileExists(atPath: baseURL.path) {
            let existing = (try? FileManager.default.contentsOfDirectory(
                at: baseURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
            )) ?? []
            if let oldDir = existing.first(where: {
                $0.lastPathComponent.hasSuffix("_\(shortID)") && $0 != targetDir
            }) {
                try FileManager.default.moveItem(at: oldDir, to: targetDir)
            }
        }
        try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
        // Heal audio paths that still point at a pre-rename folder: the folder move
        // above relocates the files, so any stored path whose file is gone but whose
        // filename exists in the current folder is rewritten. Without this, renaming
        // a session permanently breaks transcription ("audio file not found").
        session.audioFilePaths = session.audioFilePaths.map { path in
            guard !FileManager.default.fileExists(atPath: path) else { return path }
            let healed = targetDir.appendingPathComponent(
                URL(fileURLWithPath: path).lastPathComponent
            ).path
            return FileManager.default.fileExists(atPath: healed) ? healed : path
        }
        let fileURL = targetDir.appendingPathComponent("session.json")
        let data = try encoder.encode(session)
        try data.write(to: fileURL, options: .atomic)
    }

    public func loadAll() throws -> [MeetingSession] {
        guard FileManager.default.fileExists(atPath: baseURL.path) else { return [] }
        let contents = try FileManager.default.contentsOfDirectory(
            at: baseURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        )
        let sessions: [MeetingSession] = contents.compactMap { url in
            let sessionFile = url.appendingPathComponent("session.json")
            guard let data = try? Data(contentsOf: sessionFile) else { return nil }
            return try? decoder.decode(MeetingSession.self, from: data)
        }
        return sessions.sorted { $0.date > $1.date }
    }

    public func load(id: UUID) throws -> MeetingSession? {
        try loadAll().first { $0.id == id }
    }

    /// Updates only the user-authored editor fields on the latest session so a
    /// later transcript/summary regeneration cannot restore stale private notes.
    /// Generated transcript and summary data remain untouched.
    @discardableResult
    public func updateEditorContent(
        id: UUID,
        title: String,
        personalNotes: String
    ) throws -> MeetingSession? {
        guard var session = try load(id: id) else { return nil }
        session.title = title
        session.personalNotes = personalNotes
        try save(session)
        return session
    }

    public func delete(_ session: MeetingSession) throws {
        let dir = sessionURL(for: session)
        guard FileManager.default.fileExists(atPath: dir.path) else { return }
        try FileManager.default.removeItem(at: dir)
    }

    @discardableResult
    public func renameSpeaker(in sessionID: UUID, from oldName: String, to newName: String) throws -> MeetingSession? {
        let trimmedOldName = oldName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNewName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedOldName.isEmpty, !trimmedNewName.isEmpty else { return try load(id: sessionID) }
        guard var session = try load(id: sessionID) else { return nil }

        var didChange = false
        session.transcriptSegments = session.transcriptSegments.map { segment in
            guard segment.speaker == trimmedOldName else { return segment }
            var renamed = segment
            renamed.speaker = trimmedNewName
            didChange = true
            return renamed
        }

        guard didChange else { return session }
        try save(session)
        return session
    }

    // Marks any in-progress sessions as failed — call on app launch to recover from interruptions.
    public func recoverInterruptedSessions() throws {
        let sessions = try loadAll()
        for var session in sessions {
            guard session.status == .recording || session.status == .paused else { continue }
            session.status = .failed
            try save(session)
        }
    }
}
