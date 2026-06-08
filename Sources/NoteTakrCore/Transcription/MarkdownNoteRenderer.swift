import Foundation

public struct MarkdownNoteRenderer {
    public static func render(session: MeetingSession) -> String {
        var lines: [String] = []

        lines.append("# \(session.title)")
        lines.append("")

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        dateFormatter.timeStyle = .short
        lines.append("**Date:** \(dateFormatter.string(from: session.date))")
        lines.append("**Status:** \(session.status.rawValue)")
        lines.append("")

        if !session.audioSourceStatuses.isEmpty {
            lines.append("## Audio Sources")
            lines.append("")
            for status in session.audioSourceStatuses {
                if status.isPresent {
                    var parts: [String] = []
                    if let dur = status.durationSeconds {
                        let mins = Int(dur) / 60
                        let secs = Int(dur) % 60
                        parts.append(String(format: "%d:%02d", mins, secs))
                    }
                    if let bytes = status.fileSizeBytes {
                        parts.append(formatBytes(bytes))
                    }
                    let detail = parts.isEmpty ? "Captured" : "Captured (\(parts.joined(separator: " · ")))"
                    lines.append("- **\(status.source.displayName):** \(detail)")
                } else if let reason = status.missingReason {
                    lines.append("- **\(status.source.displayName):** Not captured — \(reason)")
                } else {
                    lines.append("- **\(status.source.displayName):** Not captured")
                }
            }
            lines.append("")
        } else if !session.audioFilePaths.isEmpty {
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

    private static func formatBytes(_ bytes: Int64) -> String {
        let kb = Double(bytes) / 1024
        if kb < 1024 {
            return String(format: "%.0f KB", kb)
        }
        return String(format: "%.1f MB", kb / 1024)
    }
}
