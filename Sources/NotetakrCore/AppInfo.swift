import Foundation

/// Static, platform-independent information about the application.
///
/// This lives in `NotetakrCore` so it can be exercised by Linux-compatible
/// unit tests and shared by the native macOS UI layer.
public enum AppInfo {
    /// Human-readable product name.
    public static let name = "Notetakr"

    /// Semantic version of the MVP build.
    public static let version = "0.1.0"

    /// Short tagline describing what the app does.
    public static let tagline = "Local-first meeting notes for macOS"
}
