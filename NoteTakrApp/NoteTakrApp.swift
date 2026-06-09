import AppKit
import SwiftUI

@main
struct NoteTakrApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        Window("NoteTakr", id: "main") {
            MainWindowView()
                .environmentObject(model)
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    model.showWindow(tab: .settings)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
