import AppKit
import Carbon.HIToolbox

/// Registers a single system-wide keyboard shortcut using the Carbon Hot Key
/// API. Unlike `NSEvent` global monitors this does not require Accessibility
/// permission, which is the right trade-off for a "summon my note" shortcut.
///
/// Only one hot key is needed app-wide, so the C callback dispatches through a
/// shared instance rather than threading a context pointer through Carbon.
final class GlobalHotkey {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let handler: () -> Void

    /// The live instance the C callback forwards to. There is at most one.
    private static var current: GlobalHotkey?

    /// - Parameters:
    ///   - keyCode: a virtual key code (e.g. `kVK_ANSI_N`).
    ///   - modifiers: Carbon modifier mask (e.g. `cmdKey | optionKey`).
    ///   - handler: invoked on the main thread when the shortcut fires.
    init(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        self.handler = handler
        GlobalHotkey.current = self
        register(keyCode: keyCode, modifiers: modifiers)
    }

    private func register(keyCode: UInt32, modifiers: UInt32) {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, _ -> OSStatus in
                DispatchQueue.main.async {
                    GlobalHotkey.current?.handler()
                }
                return noErr
            },
            1,
            &eventType,
            nil,
            &eventHandler
        )

        // Signature 'NOTE' (FourCharCode) keeps this hot key distinct.
        let hotKeyID = EventHotKeyID(signature: 0x4E4F_5445, id: 1)
        RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
        if GlobalHotkey.current === self { GlobalHotkey.current = nil }
    }
}
