import XCTest
import Combine
import NoteTakrKit
@testable import NoteTakr

// MARK: - Fake registrar for testing

private final class FakeRegistrar: HotkeyRegistering {
    var registerCallCount = 0
    var unregisterCallCount = 0
    var lastRegisteredCombo: HotkeyCombo?
    var registeredAction: (() -> Void)?
    var registerResult = true

    func register(combo: HotkeyCombo, action: @escaping () -> Void) -> Bool {
        registerCallCount += 1
        lastRegisteredCombo = combo
        registeredAction = action
        return registerResult
    }

    func unregister() {
        unregisterCallCount += 1
        registeredAction = nil
    }
}

// MARK: - PanelToggleCoordinatorTests

@MainActor
final class PanelToggleCoordinatorTests: XCTestCase {

    // MARK: - Toggle state machine

    func testToggleWhenHiddenCallsShow() {
        let registrar = FakeRegistrar()
        let coordinator = PanelToggleCoordinator(registrar: registrar)
        var showCount = 0, hideCount = 0
        coordinator.getPanelVisible = { false }
        coordinator.showPanel = { showCount += 1 }
        coordinator.hidePanel = { hideCount += 1 }

        coordinator.toggle()

        XCTAssertEqual(showCount, 1)
        XCTAssertEqual(hideCount, 0)
    }

    func testToggleWhenVisibleCallsHide() {
        let registrar = FakeRegistrar()
        let coordinator = PanelToggleCoordinator(registrar: registrar)
        var showCount = 0, hideCount = 0
        coordinator.getPanelVisible = { true }
        coordinator.showPanel = { showCount += 1 }
        coordinator.hidePanel = { hideCount += 1 }
        coordinator.flushPendingSave = {}

        coordinator.toggle()

        XCTAssertEqual(showCount, 0)
        XCTAssertEqual(hideCount, 1)
    }

    func testHideFlushesBeforeHiding() {
        let registrar = FakeRegistrar()
        let coordinator = PanelToggleCoordinator(registrar: registrar)
        var order: [String] = []
        coordinator.flushPendingSave = { order.append("flush") }
        coordinator.hidePanel = { order.append("hide") }

        coordinator.hide()

        XCTAssertEqual(order, ["flush", "hide"])
    }

    func testHideWithNoFlushCallbackDoesNotCrash() {
        let registrar = FakeRegistrar()
        let coordinator = PanelToggleCoordinator(registrar: registrar)
        var hideCount = 0
        coordinator.hidePanel = { hideCount += 1 }

        coordinator.hide()

        XCTAssertEqual(hideCount, 1)
    }

    func testShowCallsShowPanel() {
        let registrar = FakeRegistrar()
        let coordinator = PanelToggleCoordinator(registrar: registrar)
        var showCount = 0
        coordinator.showPanel = { showCount += 1 }

        coordinator.show()

        XCTAssertEqual(showCount, 1)
    }

    // MARK: - Hotkey registration

    func testUpdateHotkeyRegistersWithRegistrar() throws {
        let registrar = FakeRegistrar()
        let coordinator = PanelToggleCoordinator(registrar: registrar)
        let combo = try HotkeyCombo.parse("⌃⌥⌘N")

        coordinator.updateHotkey(combo)

        XCTAssertEqual(registrar.registerCallCount, 1)
        XCTAssertEqual(registrar.lastRegisteredCombo, combo)
    }

    func testUpdateHotkeysRegistersPanelAndRecordingHotkeys() throws {
        let panelRegistrar = FakeRegistrar()
        let recordingRegistrar = FakeRegistrar()
        let coordinator = PanelToggleCoordinator(
            panelRegistrar: panelRegistrar,
            recordingRegistrar: recordingRegistrar
        )
        let panelCombo = try HotkeyCombo.parse("⌃⌥⌘N")
        let recordingCombo = try HotkeyCombo.parse("⌃⌥⌘R")

        coordinator.updateHotkeys(panelToggle: panelCombo, recordingStart: recordingCombo)

        XCTAssertEqual(panelRegistrar.registerCallCount, 1)
        XCTAssertEqual(panelRegistrar.lastRegisteredCombo, panelCombo)
        XCTAssertEqual(recordingRegistrar.registerCallCount, 1)
        XCTAssertEqual(recordingRegistrar.lastRegisteredCombo, recordingCombo)
        XCTAssertEqual(recordingRegistrar.unregisterCallCount, 0)
    }

    func testRegistrationResultNotifiesCallback() throws {
        let panelRegistrar = FakeRegistrar()
        let recordingRegistrar = FakeRegistrar()
        recordingRegistrar.registerResult = false
        let coordinator = PanelToggleCoordinator(
            panelRegistrar: panelRegistrar,
            recordingRegistrar: recordingRegistrar
        )
        var events: [(HotkeyRegistrationPurpose, HotkeyCombo, Bool)] = []
        coordinator.hotkeyRegistrationChanged = { events.append(($0, $1, $2)) }
        let panelCombo = try HotkeyCombo.parse("⌃⌥⌘N")
        let recordingCombo = try HotkeyCombo.parse("⌃⌥⌘R")

        coordinator.updateHotkeys(panelToggle: panelCombo, recordingStart: recordingCombo)

        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0].0, .panelToggle)
        XCTAssertEqual(events[0].1, panelCombo)
        XCTAssertTrue(events[0].2)
        XCTAssertEqual(events[1].0, .recordingStart)
        XCTAssertEqual(events[1].1, recordingCombo)
        XCTAssertFalse(events[1].2)
    }

    func testConflictingHotkeysUnregisterRecordingHotkey() throws {
        let panelRegistrar = FakeRegistrar()
        let recordingRegistrar = FakeRegistrar()
        let coordinator = PanelToggleCoordinator(
            panelRegistrar: panelRegistrar,
            recordingRegistrar: recordingRegistrar
        )
        let combo = try HotkeyCombo.parse("⌃⌥⌘N")

        coordinator.updateHotkeys(panelToggle: combo, recordingStart: combo)

        XCTAssertEqual(panelRegistrar.registerCallCount, 1)
        XCTAssertEqual(panelRegistrar.lastRegisteredCombo, combo)
        XCTAssertEqual(recordingRegistrar.registerCallCount, 0)
        XCTAssertEqual(recordingRegistrar.unregisterCallCount, 1)
    }

    func testRecordingHotkeyActionStartsRecording() async throws {
        let panelRegistrar = FakeRegistrar()
        let recordingRegistrar = FakeRegistrar()
        let coordinator = PanelToggleCoordinator(
            panelRegistrar: panelRegistrar,
            recordingRegistrar: recordingRegistrar
        )
        let combo = try HotkeyCombo.parse("⌃⌥⌘R")
        var startCount = 0
        coordinator.startRecording = { startCount += 1 }

        coordinator.updateRecordingHotkey(combo)
        recordingRegistrar.registeredAction?()
        await Task.yield()

        XCTAssertEqual(startCount, 1)
    }

    func testHotkeyReregistrationOnSettingsChange() throws {
        let registrar = FakeRegistrar()
        let coordinator = PanelToggleCoordinator(registrar: registrar)
        let combo1 = try HotkeyCombo.parse("⌃⌥⌘N")
        let combo2 = try HotkeyCombo.parse("⌃⌥⌘M")

        coordinator.updateHotkey(combo1)
        coordinator.updateHotkey(combo2)

        XCTAssertEqual(registrar.registerCallCount, 2)
        XCTAssertEqual(registrar.lastRegisteredCombo, combo2)
    }

    // MARK: - Appearance change: exactly one re-skin per setAppearance call

    func testAppearanceChangeAppliesExactlyOneReSkin() throws {
        let (vm, ctx) = makeSettingsVM()

        var changeCount = 0
        let cancellable = vm.$currentAppearance.dropFirst().sink { _ in changeCount += 1 }
        defer { cancellable.cancel() }

        vm.setAppearance(.dark)

        XCTAssertEqual(changeCount, 1, "Exactly one re-skin per setAppearance call")
        XCTAssertEqual(vm.currentAppearance, .dark)
        XCTAssertEqual(ctx.settings.appearance, .dark)
    }

    func testAppearanceChangePersistsToStore() throws {
        let (vm, ctx) = makeSettingsVM()
        XCTAssertEqual(vm.currentAppearance, .glass) // default

        vm.setAppearance(.light)

        XCTAssertEqual(ctx.settings.appearance, .light)
        XCTAssertEqual(vm.currentAppearance, .light)
    }

    func testHotkeyChangeNotifiesCallback() throws {
        let (vm, _) = makeSettingsVM()
        var receivedCombo: HotkeyCombo?
        vm.onHotkeyChange = { receivedCombo = $0 }

        let combo = try HotkeyCombo.parse("⌃⌥⌘M")
        vm.setHotkey(combo)

        XCTAssertEqual(receivedCombo, combo)
    }

    func testRecordingHotkeyChangeNotifiesCallback() throws {
        let (vm, _) = makeSettingsVM()
        var receivedCombo: HotkeyCombo?
        vm.onRecordingHotkeyChange = { receivedCombo = $0 }

        let combo = try HotkeyCombo.parse("⌃⌥⌘R")
        vm.setRecordingHotkey(combo)

        XCTAssertEqual(receivedCombo, combo)
    }

    // MARK: - Helpers

    private struct TestCtx {
        let spy: SpyHotkeyStore
        let settings: AppSettingsStore
    }

    private func makeSettingsVM() -> (SettingsSheetViewModel, TestCtx) {
        let spy = SpyHotkeyStore()
        var note = MeetingNote(id: "n1", title: "T", date: Date())
        spy.notes["n1"] = note
        let bridge = FrontmatterPresenterBridge(store: spy)
        bridge.load(note: note)

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PanelCoordTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let settings = AppSettingsStore(root: dir)

        let vm = SettingsSheetViewModel(frontmatterBridge: bridge, appSettings: settings)
        return (vm, TestCtx(spy: spy, settings: settings))
    }
}

// MARK: - Spy note store

private final class SpyHotkeyStore: NoteStoring, @unchecked Sendable {
    var notes: [String: MeetingNote] = [:]
    func load(id: String) throws -> MeetingNote? { notes[id] }
    func save(_ note: MeetingNote) throws { notes[note.id] = note }
}
