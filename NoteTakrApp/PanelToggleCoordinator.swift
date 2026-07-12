import Foundation
import NoteTakrKit

// MARK: - HotkeyRegistering

/// Abstracts global hotkey registration so the coordinator stays testable.
protocol HotkeyRegistering: AnyObject {
    @discardableResult
    func register(combo: HotkeyCombo, action: @escaping () -> Void) -> Bool
    func unregister()
}

enum HotkeyRegistrationPurpose: Equatable {
    case panelToggle
    case recordingStart
}

// MARK: - PanelToggleCoordinator

/// Manages panel show/hide state and global hotkey lifecycle.
/// Dependencies are injected via callbacks so the state machine is testable
/// with a FakeHotkeyRegistrar without needing any AppKit types.
@MainActor
final class PanelToggleCoordinator {
    private let panelRegistrar: any HotkeyRegistering
    private let recordingRegistrar: (any HotkeyRegistering)?

    var getPanelVisible: (() -> Bool)?
    var showPanel: (() -> Void)?
    var hidePanel: (() -> Void)?
    var flushPendingSave: (() -> Void)?
    var startRecording: (() -> Void)?
    var hotkeyRegistrationChanged: ((HotkeyRegistrationPurpose, HotkeyCombo, Bool) -> Void)?

    init(registrar: any HotkeyRegistering) {
        self.panelRegistrar = registrar
        self.recordingRegistrar = nil
    }

    init(panelRegistrar: any HotkeyRegistering, recordingRegistrar: any HotkeyRegistering) {
        self.panelRegistrar = panelRegistrar
        self.recordingRegistrar = recordingRegistrar
    }

    func toggle() {
        if getPanelVisible?() == true {
            hide()
        } else {
            show()
        }
    }

    func show() {
        showPanel?()
    }

    func hide() {
        flushPendingSave?()
        hidePanel?()
    }

    @discardableResult
    func updateHotkey(_ combo: HotkeyCombo) -> Bool {
        let registered = panelRegistrar.register(combo: combo) { [weak self] in
            Task { @MainActor [weak self] in
                self?.toggle()
            }
        }
        hotkeyRegistrationChanged?(.panelToggle, combo, registered)
        return registered
    }

    @discardableResult
    func updateRecordingHotkey(_ combo: HotkeyCombo) -> Bool {
        guard let recordingRegistrar else { return false }
        let registered = recordingRegistrar.register(combo: combo) { [weak self] in
            Task { @MainActor [weak self] in
                self?.startRecording?()
            }
        }
        hotkeyRegistrationChanged?(.recordingStart, combo, registered)
        return registered
    }

    func updateHotkeys(panelToggle: HotkeyCombo, recordingStart: HotkeyCombo) {
        updateHotkey(panelToggle)
        guard panelToggle != recordingStart else {
            recordingRegistrar?.unregister()
            return
        }
        updateRecordingHotkey(recordingStart)
    }
}
