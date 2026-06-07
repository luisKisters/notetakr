#if os(macOS)
import SwiftUI
import NotetakrAppKit

/// Menu-bar app entry point. Kept intentionally thin — all UI and state live in
/// `NotetakrAppKit` so they remain unit-testable.
struct NotetakrApp: App {
    var body: some Scene {
        NotetakrScene()
    }
}

NotetakrApp.main()
#else
// On Linux the GUI app does not exist; this stub lets the executable target
// compile so `swift build`/`swift test` succeed in the Linux CI container.
import NotetakrCore

print("\(AppInfo.name) \(AppInfo.version) — macOS app. Build on macOS to run the UI.")
#endif
