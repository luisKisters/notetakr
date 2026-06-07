#if os(macOS)
import Foundation
import Observation
import NotetakrCore

/// Top-level observable state for the menu-bar app.
///
/// For Task 0 this only tracks a placeholder recording flag so the UI has
/// something to bind to. Real session/recording state arrives in later tasks.
///
/// Intentionally not `@MainActor`-isolated: SwiftUI evaluates a scene's `@State`
/// default value in a nonisolated context, so a main-actor `init` would not be
/// callable there. The model is only ever mutated from SwiftUI view bodies
/// (already on the main actor).
@Observable
public final class AppModel {
    /// Whether a (placeholder) recording is currently active.
    public private(set) var isRecording = false

    public init() {}

    /// Toggle the placeholder recording state. Wired to real lifecycle in Task 3.
    public func toggleRecording() {
        isRecording.toggle()
    }

    /// Label shown on the primary menu-bar action button.
    public var primaryActionTitle: String {
        isRecording ? "Stop Recording" : "Start Recording"
    }
}
#endif
