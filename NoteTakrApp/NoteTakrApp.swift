import AppKit
import SwiftUI

@main
struct NoteTakrApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
        .commands {
            NoteTakrSettingsCommands()
        }
    }
}

struct NoteTakrSettingsCommands: Commands {
    @Environment(\.openSettings) private var openSettings

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            SettingsLink {
                Text("Settings...")
            }
            .onReceive(NotificationCenter.default.publisher(for: .noteTakrShowSettingsWindow)) { _ in
                openSettings()
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
}
