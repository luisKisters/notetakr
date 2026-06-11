import Foundation

// MARK: - Key representation

/// Platform-agnostic symbolic key + modifier set, suitable for Linux unit tests.
public enum AppKey: Equatable {
    case cmdN
    case cmdK
    case cmdComma
    case escape
}

// MARK: - Context

/// Which overlay (if any) is currently visible in the editor window.
public enum AppKeyContext: Equatable {
    case editorFocused
    case switcherVisible
    case settingsVisible
}

// MARK: - Intent

/// High-level action the app should perform in response to a key event.
public enum AppKeyIntent: Equatable {
    case newNote
    case openSettings
    case toggleSwitcher
    /// Dismiss whichever overlay is currently visible.
    case dismissOverlay
}

// MARK: - Router

/// Maps symbolic key combos to app intents given the current overlay context.
/// Pure value type with no AppKit / SwiftUI dependency — fully testable on Linux.
public enum KeyCommandRouter {
    public static func intent(for key: AppKey, context: AppKeyContext) -> AppKeyIntent? {
        switch key {
        case .cmdN:
            return .newNote
        case .cmdK:
            return .toggleSwitcher
        case .cmdComma:
            return .openSettings
        case .escape:
            switch context {
            case .switcherVisible, .settingsVisible:
                return .dismissOverlay
            case .editorFocused:
                return nil
            }
        }
    }
}
