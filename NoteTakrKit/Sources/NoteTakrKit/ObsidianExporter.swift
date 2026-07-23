import Foundation

public struct ObsidianTranscriptSegment: Equatable, Sendable {
    public var timestamp: TimeInterval
    public var speaker: String?
    public var text: String

    public init(timestamp: TimeInterval, speaker: String? = nil, text: String) {
        self.timestamp = timestamp
        self.speaker = speaker
        self.text = text
    }
}

public struct ObsidianExportDocument: Equatable {
    public var note: MeetingNote
    public var notes: String
    public var summary: String?
    public var transcript: [ObsidianTranscriptSegment]

    public init(
        note: MeetingNote,
        notes: String? = nil,
        summary: String? = nil,
        transcript: [ObsidianTranscriptSegment] = []
    ) {
        self.note = note
        self.notes = notes ?? note.body
        self.summary = summary
        self.transcript = transcript
    }
}

public enum ObsidianExportError: LocalizedError, Equatable {
    case destinationIsNotDirectory(String)
    case destinationIsNotWritable(String)
    case invalidFileName

    public var errorDescription: String? {
        switch self {
        case .destinationIsNotDirectory(let path):
            return "The Obsidian destination is not a folder: \(path)"
        case .destinationIsNotWritable(let path):
            return "NoteTakr cannot write to the Obsidian folder: \(path)"
        case .invalidFileName:
            return "The Obsidian filename template produced an empty filename."
        }
    }
}

/// Renders NoteTakr meetings into ordinary Markdown files that Obsidian can index.
/// A private HTML marker keeps one stable file per meeting without adding visible
/// frontmatter fields or requiring a database inside the vault.
public final class ObsidianExporter: @unchecked Sendable {
    public static let defaultFileNameTemplate = "{{date}} {{title}}"

    public static let defaultTemplate = """
    ---
    tags:
      - meeting
    people:
    {{people_yaml}}
    Date: {{date}}
    location: {{location}}
    source: {{meeting_link}}
    ---
    # {{title}}

    ## Notes
    {{notes}}

    ## Summary
    {{summary}}

    ## Transcript
    {{transcript}}
    """

    public static let supportedPlaceholders = [
        "{{title}}", "{{date}}", "{{time}}", "{{datetime}}", "{{id}}",
        "{{notes}}", "{{summary}}", "{{transcript}}", "{{participants}}",
        "{{participant_links}}", "{{people_yaml}}", "{{location}}",
        "{{meeting_link}}", "{{calendar_event}}",
    ]

    private let fileManager: FileManager
    private let calendar: Calendar
    private let timeZone: TimeZone

    public init(
        fileManager: FileManager = .default,
        calendar: Calendar = .current,
        timeZone: TimeZone = .current
    ) {
        self.fileManager = fileManager
        self.calendar = calendar
        self.timeZone = timeZone
    }

    @discardableResult
    public func export(
        _ document: ObsidianExportDocument,
        to directory: URL,
        template: String = ObsidianExporter.defaultTemplate,
        fileNameTemplate: String = ObsidianExporter.defaultFileNameTemplate
    ) throws -> URL {
        try validate(directory: directory)

        let renderedFileName = render(fileNameTemplate, document: document)
        let baseName = Self.sanitizeFileName(renderedFileName)
        guard !baseName.isEmpty else { throw ObsidianExportError.invalidFileName }

        let marker = Self.marker(for: document.note.id)
        let existingURL = try existingExport(in: directory, marker: marker)
        let preferredURL = directory.appendingPathComponent(baseName).appendingPathExtension("md")
        let targetURL = try availableTarget(
            preferredURL: preferredURL,
            existingURL: existingURL,
            marker: marker
        )

        var markdown = render(template, document: document)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        markdown = marker + "\n" + markdown + "\n"

        try Data(markdown.utf8).write(to: targetURL, options: .atomic)
        if let existingURL,
           existingURL.standardizedFileURL.path != targetURL.standardizedFileURL.path {
            try fileManager.removeItem(at: existingURL)
        }
        return targetURL
    }

    public func render(_ template: String, document: ObsidianExportDocument) -> String {
        let note = document.note
        let participantNames = note.participants.map(\.displayName)
        let links = participantNames.map(Self.obsidianLink).joined(separator: ", ")
        let peopleYAML = participantNames.isEmpty
            ? "  []"
            : participantNames.map { "  - \"\(Self.escapeYAML(Self.obsidianLink($0)))\"" }.joined(separator: "\n")

        let replacements: [String: String] = [
            "{{title}}": note.title,
            "{{date}}": format(note.date, pattern: "yyyy-MM-dd"),
            "{{time}}": format(note.date, pattern: "HH:mm"),
            "{{datetime}}": format(note.date, pattern: "yyyy-MM-dd HH:mm"),
            "{{id}}": note.id,
            "{{notes}}": document.notes,
            "{{summary}}": document.summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            "{{transcript}}": Self.renderTranscript(document.transcript),
            "{{participants}}": participantNames.joined(separator: ", "),
            "{{participant_links}}": links,
            "{{people_yaml}}": peopleYAML,
            "{{location}}": note.locationText ?? note.location?.rawValue ?? "",
            "{{meeting_link}}": note.meetingLink ?? "",
            "{{calendar_event}}": note.calendarEvent ?? "",
        ]

        return replacements.reduce(template) { partial, pair in
            partial.replacingOccurrences(of: pair.key, with: pair.value)
        }
    }

    public static func sanitizeFileName(_ value: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/:\\?%*|\"<>\0")
        let filtered = value.unicodeScalars
            .map { forbidden.contains($0) || CharacterSet.newlines.contains($0) ? " " : String($0) }
            .joined()
        let collapsed = filtered
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        return String(collapsed.prefix(180))
    }

    private func validate(directory: URL) throws {
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory)
        if !exists {
            do {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            } catch {
                throw ObsidianExportError.destinationIsNotWritable(directory.path)
            }
        } else if !isDirectory.boolValue {
            throw ObsidianExportError.destinationIsNotDirectory(directory.path)
        }

        guard fileManager.isWritableFile(atPath: directory.path) else {
            throw ObsidianExportError.destinationIsNotWritable(directory.path)
        }
    }

    private func existingExport(in directory: URL, marker: String) throws -> URL? {
        let files = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        for file in files where file.pathExtension.lowercased() == "md" {
            guard let handle = try? FileHandle(forReadingFrom: file) else { continue }
            defer { try? handle.close() }
            let prefix = try handle.read(upToCount: 512) ?? Data()
            if String(decoding: prefix, as: UTF8.self).contains(marker) {
                return file
            }
        }
        return nil
    }

    private func availableTarget(preferredURL: URL, existingURL: URL?, marker: String) throws -> URL {
        if existingURL?.standardizedFileURL.path == preferredURL.standardizedFileURL.path
            || !fileManager.fileExists(atPath: preferredURL.path) {
            return preferredURL
        }
        if let prefix = try? Data(contentsOf: preferredURL, options: .mappedIfSafe).prefix(512),
           String(decoding: prefix, as: UTF8.self).contains(marker) {
            return preferredURL
        }

        let directory = preferredURL.deletingLastPathComponent()
        let base = preferredURL.deletingPathExtension().lastPathComponent
        for suffix in 2...9_999 {
            let candidate = directory
                .appendingPathComponent("\(base) \(suffix)")
                .appendingPathExtension("md")
            if existingURL?.standardizedFileURL.path == candidate.standardizedFileURL.path
                || !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        throw ObsidianExportError.invalidFileName
    }

    private func format(_ date: Date, pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }

    private static func renderTranscript(_ segments: [ObsidianTranscriptSegment]) -> String {
        segments
            .sorted { $0.timestamp < $1.timestamp }
            .map { segment in
                let seconds = max(0, Int(segment.timestamp))
                let stamp = String(format: "%02d:%02d", seconds / 60, seconds % 60)
                let speaker = segment.speaker?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let speaker, !speaker.isEmpty {
                    return "- **[\(stamp)] \(speaker):** \(segment.text)"
                }
                return "- **[\(stamp)]** \(segment.text)"
            }
            .joined(separator: "\n")
    }

    private static func obsidianLink(_ name: String) -> String {
        let safe = name.replacingOccurrences(of: "]]", with: "")
        return "[[\(safe)]]"
    }

    private static func escapeYAML(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func marker(for noteID: String) -> String {
        "<!-- notetakr:\(noteID) -->"
    }
}
