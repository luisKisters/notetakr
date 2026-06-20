import Foundation

public final class NoteStore: NoteStoring, NoteDeleting {
    public let root: URL
    private let fileManager = FileManager.default

    public init(root: URL) {
        self.root = root
    }

    // MARK: - Public API

    public func list() throws -> [MeetingNote] {
        guard fileManager.fileExists(atPath: root.path) else { return [] }
        let contents = try fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        )
        var notes: [MeetingNote] = []
        for folderURL in contents {
            let noteFile = folderURL.appendingPathComponent("note.md")
            guard fileManager.fileExists(atPath: noteFile.path) else { continue }
            if let note = try? loadNoteFile(at: noteFile, folderURL: folderURL) {
                notes.append(note)
            }
        }
        return notes.sorted { $0.date > $1.date }
    }

    public func load(id: String) throws -> MeetingNote? {
        guard let folderURL = try findFolder(forID: id) else { return nil }
        let noteFile = folderURL.appendingPathComponent("note.md")
        return try loadNoteFile(at: noteFile, folderURL: folderURL)
    }

    public func save(_ note: MeetingNote) throws {
        let targetFolder = try resolveFolder(for: note)
        let noteFile = targetFolder.appendingPathComponent("note.md")
        let text = FrontmatterSerializer.render(note: note)
        try Data(text.utf8).write(to: noteFile, options: .atomic)
    }

    public func create(title: String, date: Date) throws -> MeetingNote {
        let note = MeetingNote(id: UUID().uuidString, title: title, date: date)
        try save(note)
        return note
    }

    /// Removes the note's on-disk folder. No-op if no folder matches the id.
    public func delete(id: String) throws {
        guard let folderURL = try findFolder(forID: id) else { return }
        guard fileManager.fileExists(atPath: folderURL.path) else { return }
        try fileManager.removeItem(at: folderURL)
    }

    // MARK: - Folder naming

    public static func sanitizeTitle(_ title: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ "))
        let filtered = title.unicodeScalars
            .filter { allowed.contains($0) }
            .map { String($0) }
            .joined()
        var result = filtered.trimmingCharacters(in: .whitespaces)
        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }
        result = result.replacingOccurrences(of: " ", with: "-")
        return result.isEmpty ? "unnamed" : String(result.prefix(64))
    }

    // MARK: - Private helpers

    private func folderName(for note: MeetingNote) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        let dateStr = formatter.string(from: note.date)
        let shortID = String(note.id.prefix(8))
        return "\(dateStr)_\(NoteStore.sanitizeTitle(note.title))_\(shortID)"
    }

    private func loadNoteFile(at noteFile: URL, folderURL: URL) throws -> MeetingNote {
        let text = try String(contentsOf: noteFile, encoding: .utf8)
        var note = FrontmatterSerializer.parse(fileText: text)

        if note.id.isEmpty || note.title.isEmpty {
            let sessionFile = folderURL.appendingPathComponent("session.json")
            if fileManager.fileExists(atPath: sessionFile.path),
               let migrated = migrateFromSession(sessionFile: sessionFile, body: note.body) {
                note = migrated
                let rendered = FrontmatterSerializer.render(note: note)
                try? Data(rendered.utf8).write(to: noteFile, options: .atomic)
            }
        }
        return note
    }

    private func findFolder(forID id: String) throws -> URL? {
        guard fileManager.fileExists(atPath: root.path) else { return nil }
        let shortID = String(id.prefix(8))
        let contents = try fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        )
        // Fast path: match by short ID suffix in folder name
        for folderURL in contents {
            guard folderURL.lastPathComponent.hasSuffix("_\(shortID)") else { continue }
            let noteFile = folderURL.appendingPathComponent("note.md")
            if fileManager.fileExists(atPath: noteFile.path) { return folderURL }
        }
        // Slow path: scan note.md frontmatter for matching id
        for folderURL in contents {
            let noteFile = folderURL.appendingPathComponent("note.md")
            guard fileManager.fileExists(atPath: noteFile.path),
                  let text = try? String(contentsOf: noteFile, encoding: .utf8) else { continue }
            if FrontmatterSerializer.parse(fileText: text).id == id { return folderURL }
        }
        return nil
    }

    private func resolveFolder(for note: MeetingNote) throws -> URL {
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let targetName = folderName(for: note)
        let targetURL = root.appendingPathComponent(targetName, isDirectory: true)
        let shortID = String(note.id.prefix(8))

        if let existing = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ).first(where: { $0.lastPathComponent.hasSuffix("_\(shortID)") && $0 != targetURL }) {
            try fileManager.moveItem(at: existing, to: targetURL)
        }
        try fileManager.createDirectory(at: targetURL, withIntermediateDirectories: true)
        return targetURL
    }

    // MARK: - Migration

    private struct LegacySessionMetadata: Codable {
        let id: UUID?
        let title: String?
        let date: Date?
        let linkedEventID: String?
        let linkedEventTitle: String?
        let participants: [LegacyParticipant]?

        struct LegacyParticipant: Codable {
            let name: String
            let email: String?
        }
    }

    private func migrateFromSession(sessionFile: URL, body: String) -> MeetingNote? {
        guard let data = try? Data(contentsOf: sessionFile) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let meta = try? decoder.decode(LegacySessionMetadata.self, from: data),
              let title = meta.title, !title.isEmpty,
              let date = meta.date else { return nil }
        let id = meta.id?.uuidString ?? UUID().uuidString
        let participants = (meta.participants ?? []).map {
            Participant(name: $0.name, email: $0.email)
        }
        return MeetingNote(
            id: id,
            title: title,
            date: date,
            calendarEvent: meta.linkedEventID,
            participants: participants,
            body: body
        )
    }
}
