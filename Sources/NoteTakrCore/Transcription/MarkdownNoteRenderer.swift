import Foundation

public struct MarkdownNoteRenderer {
    public static func render(session: MeetingSession) -> String {
        var lines: [String] = []

        lines.append("# \(session.title)")
        lines.append("")

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        lines.append("**Date:** \(formatter.string(from: session.date))")
        lines.append("**Status:** \(session.status.rawValue)")
        lines.append("")

        if !session.audioFilePaths.isEmpty {
            lines.append("## Audio Files")
            lines.append("")
            for path in session.audioFilePaths {
                lines.append("- \(URL(fileURLWithPath: path).lastPathComponent)")
            }
            lines.append("")
        }

        let notes = session.personalNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !notes.isEmpty {
            lines.append("## Personal Notes")
            lines.append("")
            lines.append(notes)
            lines.append("")
        }

        if !session.transcriptSegments.isEmpty {
            lines.append("## Transcript")
            lines.append("")
            for segment in session.transcriptSegments {
                let total = Int(segment.timestamp)
                let ts = String(format: "%d:%02d", total / 60, total % 60)
                if let speaker = segment.speaker {
                    lines.append("**[\(ts)] \(speaker):** \(segment.text)")
                } else {
                    lines.append("**[\(ts)]** \(segment.text)")
                }
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }
}
