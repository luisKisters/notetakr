import Foundation
import XCTest
@testable import NoteTakrKit

final class ObsidianExporterTests: XCTestCase {
    private var root: URL!
    private var exporter: ObsidianExporter!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ObsidianExporterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        exporter = ObsidianExporter(calendar: calendar, timeZone: calendar.timeZone)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testDefaultTemplateMatchesVaultMeetingConvention() throws {
        let document = fixture(.weeklySync)
        let url = try exporter.export(document, to: root)
        let markdown = try String(contentsOf: url, encoding: .utf8)

        XCTAssertEqual(url.lastPathComponent, "2026-07-20 Product GTM Sync.md")
        XCTAssertTrue(markdown.contains("tags:\n  - meeting"))
        XCTAssertTrue(markdown.contains("  - \"[[Mara Chen]]\""))
        XCTAssertTrue(markdown.contains("Date: 2026-07-20"))
        XCTAssertTrue(markdown.contains("## Notes\nReview the lead-quality dashboard."))
        XCTAssertTrue(markdown.contains("## Summary\nThe team chose a smaller pilot."))
        XCTAssertTrue(markdown.contains("**[00:12] Mara:** The pilot should start with ten accounts."))
    }

    func testEverySupportedPlaceholderIsRendered() {
        let rendered = exporter.render(
            ObsidianExporter.supportedPlaceholders.joined(separator: "\n"),
            document: fixture(.interview)
        )

        for placeholder in ObsidianExporter.supportedPlaceholders {
            XCTAssertFalse(rendered.contains(placeholder), "Did not render \(placeholder)")
        }
        XCTAssertTrue(rendered.contains("[[Jon Bell]]"))
        XCTAssertTrue(rendered.contains("https://meet.example.test/interview"))
    }

    func testExistingMeetingIsUpdatedInsteadOfDuplicated() throws {
        var first = fixture(.weeklySync)
        let firstURL = try exporter.export(first, to: root)
        first.summary = "Updated summary after the cloud result arrived."
        let secondURL = try exporter.export(first, to: root)

        XCTAssertEqual(firstURL, secondURL)
        XCTAssertEqual(try markdownFiles().count, 1)
        XCTAssertTrue(try String(contentsOf: secondURL).contains("Updated summary"))
    }

    func testRenamedMeetingMovesItsStableExport() throws {
        var document = fixture(.weeklySync)
        let oldURL = try exporter.export(document, to: root)
        document.note.title = "Renamed GTM Sync"
        let newURL = try exporter.export(document, to: root)

        XCTAssertFalse(FileManager.default.fileExists(atPath: oldURL.path))
        XCTAssertEqual(newURL.lastPathComponent, "2026-07-20 Renamed GTM Sync.md")
        XCTAssertEqual(try markdownFiles().count, 1)
    }

    func testDifferentMeetingWithSameTitleGetsNewFile() throws {
        let first = fixture(.weeklySync)
        var second = first
        second.note.id = "meeting-02"
        second.notes = "A genuinely different meeting."

        let firstURL = try exporter.export(first, to: root)
        let secondURL = try exporter.export(second, to: root)

        XCTAssertNotEqual(firstURL, secondURL)
        XCTAssertEqual(secondURL.lastPathComponent, "2026-07-20 Product GTM Sync 2.md")
        XCTAssertEqual(try markdownFiles().count, 2)
    }

    func testCustomTemplateCanMirrorRoundtableTableStyle() throws {
        let template = """
        ---
        tags: [meeting, roundtable]
        people: [{{participant_links}}]
        Date: {{date}}
        ---
        # {{title}}
        | Topic | Result | Next step |
        | --- | --- | --- |
        {{notes}}
        """
        let url = try exporter.export(
            fixture(.roundtable),
            to: root,
            template: template,
            fileNameTemplate: "{{date}} Roundtable - {{title}}"
        )
        let markdown = try String(contentsOf: url)

        XCTAssertEqual(url.lastPathComponent, "2026-06-11 Roundtable - Revenue Operations Roundtable.md")
        XCTAssertTrue(markdown.contains("| Topic | Result | Next step |"))
        XCTAssertTrue(markdown.contains("| CRM migration | Use one source of truth |"))
    }

    func testInPersonFixtureAllowsEmptySummaryAndTranscript() throws {
        let url = try exporter.export(fixture(.inPersonCoffee), to: root)
        let markdown = try String(contentsOf: url)

        XCTAssertTrue(markdown.contains("Cafe Teststraße 4"))
        XCTAssertTrue(markdown.contains("## Summary"))
        XCTAssertTrue(markdown.contains("## Transcript"))
    }

    func testSanitizesUnsafeAndTraversalFileNames() throws {
        let url = try exporter.export(
            fixture(.interview),
            to: root,
            fileNameTemplate: "../{{title}}: follow/up?"
        )

        XCTAssertEqual(url.deletingLastPathComponent(), root)
        XCTAssertEqual(url.lastPathComponent, "Jon Bell Interview follow up.md")
    }

    func testDoesNotOverwriteUnrelatedExistingMarkdown() throws {
        let occupied = root.appendingPathComponent("2026-07-20 Product GTM Sync.md")
        try "Personal note".write(to: occupied, atomically: true, encoding: .utf8)

        let url = try exporter.export(fixture(.weeklySync), to: root)

        XCTAssertEqual(try String(contentsOf: occupied), "Personal note")
        XCTAssertEqual(url.lastPathComponent, "2026-07-20 Product GTM Sync 2.md")
    }

    func testCreatesSelectedNestedDirectory() throws {
        let nested = root.appendingPathComponent("2 Calendar/3 Meeting Notes", isDirectory: true)
        let url = try exporter.export(fixture(.weeklySync), to: nested)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testFivePrivacySafeMeetingFixturesRenderWithoutLeaksOrPlaceholders() throws {
        for kind in FixtureKind.allCases {
            let document = fixture(kind)
            let directory = root.appendingPathComponent(kind.rawValue, isDirectory: true)
            let url = try exporter.export(document, to: directory)
            let markdown = try String(contentsOf: url)

            XCTAssertTrue(markdown.contains("<!-- notetakr:\(document.note.id) -->"))
            XCTAssertFalse(markdown.contains("{{"))
            XCTAssertFalse(markdown.contains("}}"))
            XCTAssertFalse(markdown.contains("@gmail.com"))
        }
    }

    /// Opt-in smoke test for a real vault folder. The generated fake meeting is
    /// verified on disk and then removed so CI and local vaults stay clean.
    func testOptInRealVaultRoundTrip() throws {
        guard let path = ProcessInfo.processInfo.environment["NOTETAKR_OBSIDIAN_E2E_ROOT"],
              !path.isEmpty else {
            throw XCTSkip("Set NOTETAKR_OBSIDIAN_E2E_ROOT to run the real-vault round trip.")
        }

        let destination = URL(fileURLWithPath: path, isDirectory: true)
        var document = fixture(.multiSpeakerWorkshop)
        document.note.id = "obsidian-e2e-\(UUID().uuidString)"
        document.note.title = "NoteTakr Synthetic E2E"
        let url = try exporter.export(document, to: destination)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertEqual(url.deletingLastPathComponent().standardizedFileURL,
                       destination.standardizedFileURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let markdown = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(markdown.contains("# NoteTakr Synthetic E2E"))
        XCTAssertTrue(markdown.contains("<!-- notetakr:\(document.note.id) -->"))
        XCTAssertTrue(markdown.contains("**[00:07] Ari:**"))
    }

    private func markdownFiles() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "md" }
    }

    private enum FixtureKind: String, CaseIterable {
        case weeklySync
        case interview
        case roundtable
        case inPersonCoffee
        case multiSpeakerWorkshop
    }

    private func fixture(_ kind: FixtureKind) -> ObsidianExportDocument {
        let date: Date
        let title: String
        let participants: [Participant]
        let notes: String
        let summary: String?
        let transcript: [ObsidianTranscriptSegment]
        var location: String?
        var link: String?

        switch kind {
        case .weeklySync:
            date = Date(timeIntervalSince1970: 1_774_214_400) // 2026-03-20 is overridden below
            title = "Product GTM Sync"
            participants = [Participant(name: "Mara Chen"), Participant(name: "Noah Klein")]
            notes = "Review the lead-quality dashboard.\n- [ ] Send the pilot brief"
            summary = "The team chose a smaller pilot."
            transcript = [
                .init(timestamp: 12, speaker: "Mara", text: "The pilot should start with ten accounts."),
                .init(timestamp: 28, speaker: "Luis", text: "I will prepare the brief."),
            ]
        case .interview:
            date = Self.utcDate(2025, 9, 18, 14, 30)
            title = "Jon Bell Interview"
            participants = [Participant(name: "Jon Bell")]
            notes = "# Questions\n- What part of the workflow is most repetitive?"
            summary = "Jon wants fewer handoffs between research and outreach."
            transcript = [.init(timestamp: 4, speaker: "Jon", text: "The handoff is where context gets lost.")]
            link = "https://meet.example.test/interview"
        case .roundtable:
            date = Self.utcDate(2026, 6, 11, 9, 0)
            title = "Revenue Operations Roundtable"
            participants = [Participant(name: "Ava Reed"), Participant(name: "Omar Diaz")]
            notes = "| CRM migration | Use one source of truth | Validate imports |"
            summary = "Three teams agreed to validate imports before migration."
            transcript = []
        case .inPersonCoffee:
            date = Self.utcDate(2026, 7, 3, 11, 0)
            title = "Mina Coffee Chat"
            participants = [Participant(name: "Mina Park")]
            notes = "# Questions\n- What did you learn from your first launch?"
            summary = nil
            transcript = []
            location = "Cafe Teststraße 4"
        case .multiSpeakerWorkshop:
            date = Self.utcDate(2026, 4, 22, 15, 0)
            title = "Synthetic Pipeline Workshop"
            participants = [
                Participant(name: "Ari Stone"), Participant(name: "Bea Holm"),
                Participant(name: "Cleo Ward"), Participant(name: "Dev Shah"),
            ]
            notes = "# Ideas\n- Daily summaries\n- Close open loops"
            summary = "The group assigned owners to two automation experiments."
            transcript = [
                .init(timestamp: 0, speaker: "Luis", text: "Let us map the current workflow."),
                .init(timestamp: 7, speaker: "Ari", text: "The first gap is enrichment."),
                .init(timestamp: 15, speaker: "Bea", text: "The second gap is follow-up."),
                .init(timestamp: 23, speaker: "Cleo", text: "I can own the daily digest."),
            ]
        }

        // Keep this one exact so filename/date assertions stay readable.
        let exactDate = kind == .weeklySync ? Self.utcDate(2026, 7, 20, 10, 0) : date
        let note = MeetingNote(
            id: "meeting-\(kind.rawValue)",
            title: title,
            date: exactDate,
            participants: participants,
            locationText: location,
            meetingLink: link,
            body: notes
        )
        return ObsidianExportDocument(note: note, notes: notes, summary: summary, transcript: transcript)
    }

    private static func utcDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return components.date!
    }
}
