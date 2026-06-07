#if os(macOS)
import SwiftUI

/// The SwiftUI scene that backs the menu-bar app. Exposed from `NotetakrAppKit`
/// so the thin `NotetakrApp` executable can host it and tests can construct it.
public struct NotetakrScene: Scene {
    @State private var model = AppModel()

    public init() {}

    public var body: some Scene {
        MenuBarExtra("Notetakr", systemImage: "waveform") {
            MenuBarView(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}
#endif
