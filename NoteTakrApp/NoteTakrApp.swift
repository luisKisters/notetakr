import AppKit
import SwiftUI

@main
struct NoteTakrApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Panel-only app — no main window. The floating NSPanel is managed by AppDelegate.
        // Settings scene suppressed; settings are accessed via the gear in the note panel.
        Settings { EmptyView() }
            .commands {
                CommandGroup(replacing: .appSettings) { }
            }
    }
}
