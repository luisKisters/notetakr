import SwiftUI

@main
struct NoteTakrApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            Text("NoteTakr Settings")
                .frame(width: 300, height: 200)
        }
    }
}
