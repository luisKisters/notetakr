import Foundation

public enum FrontmatterSerializer {

    // MARK: - Parse

    public static func parse(fileText: String) -> MeetingNote {
        let (frontmatter, body) = splitFrontmatter(fileText)
        guard let fm = frontmatter else {
            return bodyOnlyNote(body: fileText)
        }
        return parseFrontmatter(fm, body: body)
    }

    // MARK: - Render

    public static func render(note: MeetingNote) -> String {
        var lines = ["---"]

        lines.append("id: \(note.id)")
        lines.append("title: \(quoteIfNeeded(note.title))")
        lines.append("date: \(iso8601(note.date))")
        if let end = note.end {
            lines.append("end: \(iso8601(end))")
        }
        if let cal = note.calendarEvent {
            lines.append("calendar_event: \(cal)")
        }
        if note.participants.contains(where: { trimmedNonEmpty($0.crm) != nil }) {
            lines.append("participants:")
            for participant in note.participants {
                lines.append(contentsOf: renderParticipantBlockItem(participant))
            }
        } else if !note.participants.isEmpty {
            let parts = note.participants.map { renderParticipant($0) }.joined(separator: ", ")
            lines.append("participants: [\(parts)]")
        }
        if let loc = note.location {
            lines.append("location: \(loc.rawValue)")
        }
        if let lt = note.locationText {
            lines.append("location_text: \(quoteIfNeeded(lt))")
        }
        if let ml = note.meetingLink {
            lines.append("meeting_link: \(quoteIfNeeded(ml))")
        }
        if let ip = note.inPerson {
            lines.append("in_person: \(ip ? "true" : "false")")
        }
        if let tr = note.transcribe {
            lines.append("transcribe: \(tr ? "true" : "false")")
        }
        if let lang = note.language {
            lines.append("language: \(lang.rawValue)")
        }
        if !note.vocabulary.isEmpty {
            let vocab = note.vocabulary.map { quoteIfNeeded($0) }.joined(separator: ", ")
            lines.append("vocabulary: [\(vocab)]")
        }
        for unknown in note.unknownFrontmatterKeys {
            lines.append(unknown.rawLine)
        }

        lines.append("---")
        if note.body.isEmpty {
            return lines.joined(separator: "\n") + "\n"
        }
        return lines.joined(separator: "\n") + "\n" + note.body
    }

    // MARK: - Private helpers

    private static func splitFrontmatter(_ text: String) -> (frontmatter: String?, body: String) {
        let lines = text.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else {
            return (nil, text)
        }
        var i = 1
        while i < lines.count {
            if lines[i].trimmingCharacters(in: .whitespaces) == "---" {
                let fm = lines[1..<i].joined(separator: "\n")
                let bodyLines = lines[(i + 1)...]
                var body = bodyLines.joined(separator: "\n")
                if body.hasPrefix("\n") { body = String(body.dropFirst()) }
                return (fm, body)
            }
            i += 1
        }
        return (nil, text)
    }

    private static func bodyOnlyNote(body: String) -> MeetingNote {
        return MeetingNote(id: "", title: "", date: Date(timeIntervalSince1970: 0), body: body)
    }

    private static func parseFrontmatter(_ fm: String, body: String) -> MeetingNote {
        var id = ""
        var title = ""
        var date: Date = Date(timeIntervalSince1970: 0)
        var end: Date? = nil
        var calendarEvent: String? = nil
        var participants: [Participant] = []
        var location: Location? = nil
        var locationText: String? = nil
        var meetingLink: String? = nil
        var inPerson: Bool? = nil
        var transcribe: Bool? = nil
        var language: TranscribeLanguage? = nil
        var vocabulary: [String] = []
        var unknownKeys: [(key: String, rawLine: String)] = []

        let knownKeys: Set<String> = ["id","title","date","end","calendar_event","participants","location","location_text","meeting_link","in_person","transcribe","language","vocabulary"]

        let lines = fm.components(separatedBy: "\n")
        var i = 0
        while i < lines.count {
            let rawLine = lines[i]
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { i += 1; continue }

            // Check for block list (key: then next lines start with -)
            if let colonIdx = firstColon(in: trimmed) {
                let key = String(trimmed[trimmed.startIndex..<colonIdx])
                    .trimmingCharacters(in: .whitespaces)
                let valuePart = String(trimmed[trimmed.index(after: colonIdx)...])
                    .trimmingCharacters(in: .whitespaces)

                if valuePart.isEmpty, key == "participants" {
                    let parsed = parseParticipantBlock(lines: lines, start: i + 1)
                    if !parsed.participants.isEmpty {
                        participants = parsed.participants
                        i = parsed.nextIndex
                        continue
                    }
                }

                // Peek ahead: block sequence?
                if valuePart.isEmpty {
                    var blockItems: [String] = []
                    var j = i + 1
                    while j < lines.count {
                        let bl = lines[j].trimmingCharacters(in: .whitespaces)
                        if bl.hasPrefix("- ") {
                            blockItems.append(String(bl.dropFirst(2)).trimmingCharacters(in: .whitespaces))
                            j += 1
                        } else if bl.isEmpty {
                            j += 1
                        } else {
                            break
                        }
                    }
                    if !blockItems.isEmpty {
                        i = j
                        switch key {
                        case "vocabulary":
                            vocabulary = blockItems.map { unquote($0) }
                        default:
                            let block = blockItems.map { "- \($0)" }.joined(separator: "\n")
                            unknownKeys.append((key: key, rawLine: "\(key):\n\(block)"))
                        }
                        continue
                    }
                }

                switch key {
                case "id":
                    id = unquote(valuePart)
                case "title":
                    title = unquote(valuePart)
                case "date":
                    date = parseDate(valuePart) ?? Date(timeIntervalSince1970: 0)
                case "end":
                    end = parseDate(valuePart)
                case "calendar_event":
                    calendarEvent = valuePart.isEmpty ? nil : unquote(valuePart)
                case "participants":
                    participants = parseList(valuePart).map { parseParticipant($0) }
                case "location":
                    location = parseLocation(valuePart)
                case "location_text":
                    locationText = valuePart.isEmpty ? nil : unquote(valuePart)
                case "meeting_link":
                    meetingLink = valuePart.isEmpty ? nil : unquote(valuePart)
                case "in_person":
                    inPerson = parseBool(valuePart)
                case "transcribe":
                    transcribe = parseBool(valuePart)
                case "language":
                    language = TranscribeLanguage(rawValue: unquote(valuePart))
                case "vocabulary":
                    vocabulary = parseList(valuePart).map { unquote($0) }
                default:
                    if knownKeys.contains(key) { break }
                    unknownKeys.append((key: key, rawLine: rawLine))
                }
            }
            i += 1
        }

        guard !id.isEmpty, !title.isEmpty else {
            return bodyOnlyNote(body: body)
        }

        return MeetingNote(
            id: id,
            title: title,
            date: date,
            end: end,
            calendarEvent: calendarEvent,
            participants: participants,
            location: location,
            locationText: locationText,
            meetingLink: meetingLink,
            inPerson: inPerson,
            transcribe: transcribe,
            language: language,
            vocabulary: vocabulary,
            unknownFrontmatterKeys: unknownKeys,
            body: body
        )
    }

    // Find the index of the first `:` not inside quotes
    private static func firstColon(in s: String) -> String.Index? {
        var inSingle = false
        var inDouble = false
        for idx in s.indices {
            let c = s[idx]
            if c == "'" && !inDouble { inSingle.toggle() }
            else if c == "\"" && !inSingle { inDouble.toggle() }
            else if c == ":" && !inSingle && !inDouble { return idx }
        }
        return nil
    }

    // Parse flow sequence [a, b, c] or return [s] for plain scalar
    private static func parseList(_ s: String) -> [String] {
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
            let inner = String(trimmed.dropFirst().dropLast())
            return splitFlowList(inner)
        }
        // Inline block-style on one line: `- a` is handled upstream; treat as scalar
        if trimmed.isEmpty { return [] }
        return [trimmed]
    }

    // Split a flow list respecting quotes and brackets
    private static func splitFlowList(_ s: String) -> [String] {
        var items: [String] = []
        var current = ""
        var depth = 0
        var inSingle = false
        var inDouble = false
        for c in s {
            if c == "'" && !inDouble { inSingle.toggle() }
            else if c == "\"" && !inSingle { inDouble.toggle() }
            else if (c == "[" || c == "{") && !inSingle && !inDouble { depth += 1 }
            else if (c == "]" || c == "}") && !inSingle && !inDouble { depth -= 1 }
            else if c == "," && depth == 0 && !inSingle && !inDouble {
                items.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
                continue
            }
            current.append(c)
        }
        let last = current.trimmingCharacters(in: .whitespaces)
        if !last.isEmpty { items.append(last) }
        return items
    }

    private static func parseParticipant(_ s: String) -> Participant {
        let t = unquote(s)
        if t.hasPrefix("{"), t.hasSuffix("}") {
            return parseParticipantMapping(String(t.dropFirst().dropLast()))
        }
        // Match "Name <email>"
        if t.hasSuffix(">"), let ltIdx = t.lastIndex(of: "<") {
            let name = String(t[t.startIndex..<ltIdx]).trimmingCharacters(in: .whitespaces)
            let email = String(t[t.index(after: ltIdx)..<t.index(before: t.endIndex)])
                .trimmingCharacters(in: .whitespaces)
            return Participant(name: name, email: email.isEmpty ? nil : email)
        }
        return Participant(name: t)
    }

    private static func renderParticipant(_ p: Participant) -> String {
        if let email = p.email {
            return quoteIfNeeded("\(p.name) <\(email)>")
        }
        return quoteIfNeeded(p.name)
    }

    private static func parseParticipantBlock(lines: [String], start: Int) -> (participants: [Participant], nextIndex: Int) {
        var participants: [Participant] = []
        var i = start

        while i < lines.count {
            let rawLine = lines[i]
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                i += 1
                continue
            }
            guard trimmed.hasPrefix("- ") else { break }

            let item = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            if let field = participantField(from: item) {
                var fields = [field.key: field.value]
                i += 1

                while i < lines.count {
                    let nestedRawLine = lines[i]
                    let nestedTrimmed = nestedRawLine.trimmingCharacters(in: .whitespaces)
                    if nestedTrimmed.isEmpty {
                        i += 1
                        continue
                    }
                    if nestedTrimmed.hasPrefix("- ") { break }
                    guard nestedRawLine.first?.isWhitespace == true else { break }

                    if let nestedField = participantField(from: nestedTrimmed) {
                        fields[nestedField.key] = nestedField.value
                    }
                    i += 1
                }

                participants.append(participant(fromFields: fields))
            } else {
                participants.append(parseParticipant(item))
                i += 1
            }
        }

        return (participants, i)
    }

    private static func parseParticipantMapping(_ mapping: String) -> Participant {
        var fields: [String: String] = [:]
        for item in splitFlowList(mapping) {
            if let field = participantField(from: item) {
                fields[field.key] = field.value
            }
        }
        return participant(fromFields: fields)
    }

    private static func participantField(from item: String) -> (key: String, value: String)? {
        let trimmed = item.trimmingCharacters(in: .whitespaces)
        guard let colonIdx = firstColon(in: trimmed) else { return nil }
        let key = String(trimmed[trimmed.startIndex..<colonIdx])
            .trimmingCharacters(in: .whitespaces)
        guard ["name", "email", "crm"].contains(key) else { return nil }
        let value = String(trimmed[trimmed.index(after: colonIdx)...])
            .trimmingCharacters(in: .whitespaces)
        return (key, unquote(value))
    }

    private static func participant(fromFields fields: [String: String]) -> Participant {
        let email = trimmedNonEmpty(fields["email"])
        let crm = trimmedNonEmpty(fields["crm"])
        let name = Participant.displayName(name: trimmedNonEmpty(fields["name"]), email: email)
        return Participant(name: name, email: email, crm: crm)
    }

    private static func renderParticipantBlockItem(_ participant: Participant) -> [String] {
        var lines = ["  - name: \(quoteIfNeeded(participant.name))"]
        if let email = trimmedNonEmpty(participant.email) {
            lines.append("    email: \(quoteIfNeeded(email))")
        }
        if let crm = trimmedNonEmpty(participant.crm) {
            lines.append("    crm: \(quoteIfNeeded(crm))")
        }
        return lines
    }

    private static func parseLocation(_ s: String) -> Location? {
        Location(rawValue: unquote(s))
    }

    private static func parseBool(_ s: String) -> Bool? {
        switch s.lowercased() {
        case "true", "yes", "on", "1": return true
        case "false", "no", "off", "0": return false
        default: return nil
        }
    }

    // ISO8601 with fractional-seconds off, timezone required
    private static let iso8601Formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static func parseDate(_ s: String) -> Date? {
        let t = unquote(s)
        return iso8601Formatter.date(from: t)
    }

    private static func iso8601(_ date: Date) -> String {
        iso8601Formatter.string(from: date)
    }

    private static func unquote(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("\"") && t.hasSuffix("\"") && t.count >= 2 {
            let inner = String(t.dropFirst().dropLast())
            return inner
                .replacingOccurrences(of: "\\\"", with: "\"")
                .replacingOccurrences(of: "\\\\", with: "\\")
        }
        if t.hasPrefix("'") && t.hasSuffix("'") && t.count >= 2 {
            return String(t.dropFirst().dropLast())
        }
        // Strip inline comment (` # ...`)
        if let hashIdx = t.range(of: " #") {
            return String(t[t.startIndex..<hashIdx.lowerBound]).trimmingCharacters(in: .whitespaces)
        }
        return t
    }

    // Wrap in double quotes if value contains special chars
    private static func quoteIfNeeded(_ s: String) -> String {
        let specials: Set<Character> = [":", "{", "}", "[", "]", ",", "#", "&", "*", "?", "|", "-", "<", ">", "=", "!", "%", "@", "`", "\"", "'"]
        if s.contains(where: { specials.contains($0) }) || s.trimmingCharacters(in: .whitespaces) != s {
            let escaped = s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            return "\"\(escaped)\""
        }
        return s
    }

    private static func trimmedNonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}
