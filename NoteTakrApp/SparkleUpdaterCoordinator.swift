import Foundation

#if canImport(Sparkle)
import Sparkle

/// Thin singleton that lets any part of the app trigger a Sparkle update check.
/// AppDelegate calls `configure(controller:)` once after creating the updater.
@MainActor
final class SparkleUpdaterCoordinator {
    static let shared = SparkleUpdaterCoordinator()
    private weak var controller: SPUStandardUpdaterController?

    func configure(controller: SPUStandardUpdaterController) {
        self.controller = controller
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }
}
#else
/// Stub when Sparkle is unavailable (Linux / simulator).
@MainActor
final class SparkleUpdaterCoordinator {
    static let shared = SparkleUpdaterCoordinator()
    func checkForUpdates() {}
}
#endif
