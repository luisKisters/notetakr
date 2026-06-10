import Foundation
import NoteTakrKit

// MARK: - HotkeyRegistering

/// Abstracts global hotkey registration so the coordinator stays testable.
protocol HotkeyRegistering: AnyObject {
    func register(combo: HotkeyCombo, action: @escaping () -> Void)
    func unregister()
}

// MARK: - PanelToggleCoordinator

/// Manages panel show/hide state and global hotkey lifecycle.
/// Dependencies are injected via callbacks so the state machine is testable
/// with a FakeHotkeyRegistrar without needing any AppKit types.
@MainActor
final class PanelToggleCoordinator {
    private let registrar: any HotkeyRegistering

    var getPanelVisible: (() -> Bool)?
    var showPanel: (() -> Void)?
    var hidePanel: (() -> Void)?
    var flushPendingSave: (() -> Void)?

    init(registrar: any HotkeyRegistering) {
        self.registrar = registrar
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

    func updateHotkey(_ combo: HotkeyCombo) {
        registrar.register(combo: combo) { [weak self] in
            Task { @MainActor [weak self] in
                self?.toggle()
            }
        }
    }
}
