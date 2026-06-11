import XCTest
import NoteTakrKit
@testable import NoteTakr

/// Tests for SettingsSheetViewModel covering:
/// - Scope banner only on This Meeting tab
/// - This Meeting edits write to frontmatter (spy) and never touch settings.json
/// - General edits write to settings.json and never touch the open note
/// - Language warning visibility matches Kit rule
@MainActor
final class SettingsSheetViewModelTests: XCTestCase {

    // MARK: - Scope banner

    func testBannerShownOnlyForThisMeetingTab() {
        let (vm, _) = makeVM()
        vm.selectedTab = .thisMeeting
        XCTAssertTrue(vm.showScopeBanner)

        for tab: SettingsTab in [.general, .recording, .vocabulary, .permissions] {
            vm.selectedTab = tab
            XCTAssertFalse(vm.showScopeBanner, "Banner should be hidden for \(tab)")
        }
    }

    func testNoteTitle() {
        let (vm, _) = makeVM()
        XCTAssertEqual(vm.noteTitle, "Test Meeting")
    }

    // MARK: - This Meeting writes frontmatter, NOT settings.json

    func testTranscribeThisMeetingWritesFrontmatter() throws {
        let (vm, ctx) = makeVM()
        vm.setTranscribeThisMeeting(false)

        let saved = try XCTUnwrap(ctx.spy.notes["note-1"])
        XCTAssertEqual(saved.transcribe, false, "Should write transcribe to frontmatter")
        // Settings file not touched — transcribeByDefault stays at initial value (true)
        XCTAssertEqual(ctx.settings.transcribeByDefault, true, "settings.json must not change")
    }

    func testInPersonThisMeetingWritesFrontmatter() throws {
        let (vm, ctx) = makeVM()
        vm.setInPersonThisMeeting(true)

        let saved = try XCTUnwrap(ctx.spy.notes["note-1"])
        XCTAssertEqual(saved.inPerson, true)
        XCTAssertEqual(ctx.settings.inPersonByDefault, false, "settings.json must not change")
    }

    func testLanguageThisMeetingWritesFrontmatter() throws {
        let (vm, ctx) = makeVM()
        vm.setLanguageThisMeeting(.code("de"))

        let saved = try XCTUnwrap(ctx.spy.notes["note-1"])
        XCTAssertEqual(saved.language, .code("de"))
        XCTAssertEqual(ctx.settings.defaultLanguage, .auto, "settings.json must not change")
    }

    func testUnlinkEventClearsFrontmatter() throws {
        let (vm, ctx) = makeVM(calendarEvent: "evt-123")
        vm.unlinkEvent()

        let saved = try XCTUnwrap(ctx.spy.notes["note-1"])
        XCTAssertNil(saved.calendarEvent, "calendarEvent should be cleared")
        XCTAssertEqual(ctx.settings.transcribeByDefault, true, "settings.json untouched")
    }

    func testAddVocabTermWritesFrontmatter() throws {
        let (vm, ctx) = makeVM()
        vm.addVocabularyTermThisMeeting("Acme")

        let saved = try XCTUnwrap(ctx.spy.notes["note-1"])
        XCTAssertTrue(saved.vocabulary.contains("Acme"))
    }

    func testRemoveVocabTermWritesFrontmatter() throws {
        let (vm, ctx) = makeVM(vocabulary: ["Acme", "Müller"])
        vm.removeVocabularyTermThisMeeting("Acme")

        let saved = try XCTUnwrap(ctx.spy.notes["note-1"])
        XCTAssertFalse(saved.vocabulary.contains("Acme"))
        XCTAssertTrue(saved.vocabulary.contains("Müller"))
    }

    // MARK: - General writes settings.json, NOT note frontmatter

    func testTranscribeByDefaultWritesSettings() throws {
        let (vm, ctx) = makeVM()
        vm.setTranscribeByDefault(false)

        XCTAssertEqual(ctx.settings.transcribeByDefault, false)
        // Note frontmatter should not have been set
        let note = try XCTUnwrap(ctx.spy.notes["note-1"])
        XCTAssertNil(note.transcribe, "Note transcribe must remain nil — not written by General")
    }

    func testInPersonByDefaultWritesSettings() throws {
        let (vm, ctx) = makeVM()
        vm.setInPersonByDefault(true)

        XCTAssertEqual(ctx.settings.inPersonByDefault, true)
        let note = try XCTUnwrap(ctx.spy.notes["note-1"])
        XCTAssertNil(note.inPerson, "Note inPerson must remain nil — not written by General")
    }

    func testDefaultLanguageWritesSettings() throws {
        let (vm, ctx) = makeVM()
        vm.setDefaultLanguage(.code("fr"))

        XCTAssertEqual(ctx.settings.defaultLanguage, .code("fr"))
        let note = try XCTUnwrap(ctx.spy.notes["note-1"])
        XCTAssertNil(note.language, "Note language must remain nil — not written by General")
    }

    func testLaunchAtLoginWritesSettings() {
        let (vm, ctx) = makeVM()
        vm.setLaunchAtLogin(true)

        XCTAssertEqual(ctx.settings.launchAtLogin, true)
    }

    // MARK: - Language warning matches Kit rule

    func testNoLanguageWarningWhenAutoDetect() {
        let (vm, ctx) = makeVM()
        ctx.settings.defaultLanguage = .auto
        XCTAssertFalse(vm.showLanguageWarning)
    }

    func testLanguageWarningWhenFixed() {
        let (vm, ctx) = makeVM()
        ctx.settings.defaultLanguage = .code("de")
        XCTAssertTrue(vm.showLanguageWarning)
    }

    // MARK: - Appearance (theme-driven colours)

    func testDefaultAppearanceMatchesSettings() {
        let (vm, ctx) = makeVM()
        XCTAssertEqual(vm.currentAppearance, ctx.settings.appearance,
                       "VM currentAppearance must mirror the settings store on init")
    }

    func testSetAppearanceUpdatesViewModelAndSettings() {
        let (vm, ctx) = makeVM()
        vm.setAppearance(.dark)
        XCTAssertEqual(vm.currentAppearance, .dark)
        XCTAssertEqual(ctx.settings.appearance, .dark, "settings.json must persist the appearance change")
    }

    func testSetAppearanceRoundTripsAllValues() {
        let (vm, ctx) = makeVM()
        for appearance in Appearance.allCases {
            vm.setAppearance(appearance)
            XCTAssertEqual(vm.currentAppearance, appearance, "currentAppearance must equal \(appearance) after setAppearance")
            XCTAssertEqual(ctx.settings.appearance, appearance, "settings must persist \(appearance)")
        }
    }

    func testAppearanceColorsMatchThemeForEveryCase() {
        let (vm, _) = makeVM()
        for appearance in Appearance.allCases {
            vm.setAppearance(appearance)
            let colors = Theme.colors(for: vm.currentAppearance)
            XCTAssertEqual(colors, Theme.colors(for: appearance),
                           "Theme.colors for \(appearance) must match after setAppearance")
        }
    }

    func testLightAppearancePrimaryTextIsReadable() {
        let (vm, _) = makeVM()
        vm.setAppearance(.light)
        let colors = Theme.colors(for: vm.currentAppearance)
        // Light primary text must be dark enough (low channel values = dark ink)
        XCTAssertLessThan(colors.primaryText.r, 0.15,
                          "Light primary text must be near-black for readability")
    }

    func testDarkAppearancePrimaryTextIsLight() {
        let (vm, _) = makeVM()
        vm.setAppearance(.dark)
        let colors = Theme.colors(for: vm.currentAppearance)
        XCTAssertGreaterThan(colors.primaryText.r, 0.8,
                             "Dark primary text must be near-white")
    }

    // MARK: - Tab selection model (row hit-target semantics)

    func testAllTabsCycleCorrectly() {
        let (vm, _) = makeVM()
        for tab in SettingsTab.allCases {
            vm.selectedTab = tab
            XCTAssertEqual(vm.selectedTab, tab, "selectedTab must equal \(tab) after direct assignment")
        }
    }

    func testScopeBannerReflectsTabSelection() {
        let (vm, _) = makeVM()
        vm.selectedTab = .thisMeeting
        XCTAssertTrue(vm.showScopeBanner, "Scope banner must be shown on This Meeting tab")
        vm.selectedTab = .general
        XCTAssertFalse(vm.showScopeBanner, "Scope banner must be hidden on General tab")
        vm.selectedTab = .recording
        XCTAssertFalse(vm.showScopeBanner, "Scope banner must be hidden on Recording tab")
    }

    // MARK: - Sheet lifecycle

    func testCloseHidesSheet() {
        let (vm, _) = makeVM()
        vm.isVisible = true
        vm.close()
        XCTAssertFalse(vm.isVisible)
    }

    // MARK: - Helpers

    private struct TestContext {
        let spy: SpySettingsStore
        let settings: AppSettingsStore
    }

    private func makeVM(
        calendarEvent: String? = nil,
        vocabulary: [String] = []
    ) -> (SettingsSheetViewModel, TestContext) {
        let spy = SpySettingsStore()
        var note = MeetingNote(id: "note-1", title: "Test Meeting", date: Date())
        note.calendarEvent = calendarEvent
        note.vocabulary = vocabulary
        spy.notes["note-1"] = note

        let fpBridge = FrontmatterPresenterBridge(store: spy)
        fpBridge.load(note: note)

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SettingsVMTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let settings = AppSettingsStore(root: dir)

        let vm = SettingsSheetViewModel(frontmatterBridge: fpBridge, appSettings: settings)
        return (vm, TestContext(spy: spy, settings: settings))
    }
}

// MARK: - Spy note store

private final class SpySettingsStore: NoteStoring, @unchecked Sendable {
    var notes: [String: MeetingNote] = [:]

    func load(id: String) throws -> MeetingNote? { notes[id] }
    func save(_ note: MeetingNote) throws { notes[note.id] = note }
}
