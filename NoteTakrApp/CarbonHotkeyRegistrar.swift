import AppKit
import Carbon
import NoteTakrKit

// MARK: - Carbon event callback (file scope — no captures, compatible with C function pointer)

private func carbonHotkeyCallback(
    _ callRef: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData, let event else { return OSStatus(eventNotHandledErr) }
    var pressedID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &pressedID
    )
    guard status == noErr else { return OSStatus(eventNotHandledErr) }
    let obj = Unmanaged<CarbonHotkeyRegistrar>.fromOpaque(userData).takeUnretainedValue()
    guard pressedID.id == obj.hotkeyID else { return OSStatus(eventNotHandledErr) }
    DispatchQueue.main.async { [weak obj] in obj?.fireAction() }
    return noErr
}

// MARK: - CarbonHotkeyRegistrar

/// Registers and unregisters a global keyboard shortcut using Carbon's
/// RegisterEventHotKey API. Owned for the app lifetime by PanelToggleCoordinator.
/// Pass a unique `hotkeyID` (default 1) when registering multiple global hotkeys
/// so each has a distinct (signature, id) pair and they coexist without conflict.
final class CarbonHotkeyRegistrar: HotkeyRegistering {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private(set) var currentAction: (() -> Void)?
    fileprivate let hotkeyID: UInt32

    init(hotkeyID: UInt32 = 1) {
        self.hotkeyID = hotkeyID
        installEventHandler()
    }

    deinit {
        unregister()
        if let ref = handlerRef {
            RemoveEventHandler(ref)
        }
    }

    // MARK: - HotkeyRegistering

    func register(combo: HotkeyCombo, action: @escaping () -> Void) {
        guard let keyCode = virtualKeyCode(for: combo.key) else { return }
        unregister()
        currentAction = action

        var keyID = EventHotKeyID(signature: OSType(0x4E544B52), id: hotkeyID) // 'NTKR'
        RegisterEventHotKey(
            keyCode,
            carbonModifiers(from: combo.modifiers),
            keyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        currentAction = nil
    }

    /// Invoked from the Carbon event handler on the main queue.
    func fireAction() {
        currentAction?()
    }

    // MARK: - Private

    private func installEventHandler() {
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPtr = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        InstallEventHandler(
            GetApplicationEventTarget(),
            carbonHotkeyCallback,
            1,
            &eventSpec,
            selfPtr,
            &handlerRef
        )
    }

    // MARK: - Modifier conversion

    private func carbonModifiers(from modifiers: HotkeyCombo.Modifiers) -> UInt32 {
        var mods: UInt32 = 0
        if modifiers.contains(.command) { mods |= UInt32(cmdKey) }
        if modifiers.contains(.option)  { mods |= UInt32(optionKey) }
        if modifiers.contains(.shift)   { mods |= UInt32(shiftKey) }
        if modifiers.contains(.control) { mods |= UInt32(controlKey) }
        return mods
    }

    // MARK: - Virtual key codes (US QWERTY layout)

    private func virtualKeyCode(for key: Character) -> UInt32? {
        let map: [Character: UInt32] = [
            "A": 0x00, "S": 0x01, "D": 0x02, "F": 0x03, "H": 0x04, "G": 0x05,
            "Z": 0x06, "X": 0x07, "C": 0x08, "V": 0x09, "B": 0x0B, "Q": 0x0C,
            "W": 0x0D, "E": 0x0E, "R": 0x0F, "Y": 0x10, "T": 0x11,
            "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15, "6": 0x16, "5": 0x17,
            "9": 0x19, "7": 0x1A, "8": 0x1C, "0": 0x1D,
            "O": 0x1F, "U": 0x20, "I": 0x22, "P": 0x23,
            "L": 0x25, "J": 0x26, "K": 0x28, "N": 0x2D, "M": 0x2E,
        ]
        return map[key]
    }
}
