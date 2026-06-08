// Permission state manager for microphone and system-audio (screen recording) access.
// Verified only on the macOS CI runner / physical Mac.
#if canImport(AVFoundation)
import AVFoundation
import AppKit
import NoteTakrCore

@MainActor
final class AudioPermissionManager: ObservableObject {
    @Published private(set) var microphoneStatus: PermissionStatus = .notDetermined
    @Published private(set) var systemAudioStatus: PermissionStatus = .notDetermined

    init() {
        refresh()
    }

    func refresh() {
        microphoneStatus = currentMicrophoneStatus()
        systemAudioStatus = currentSystemAudioStatus()
    }

    func requestMicrophoneAccess() async {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        microphoneStatus = granted ? .granted : .denied
    }

    /// Opens the screen recording permission pane in System Settings.
    /// Screen recording permission is required for system-audio capture via ScreenCaptureKit.
    func requestSystemAudioAccess() {
        CGRequestScreenCaptureAccess()
        refresh()
    }

    private func currentMicrophoneStatus() -> PermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return .granted
        case .denied, .restricted: return .denied
        default: return .notDetermined
        }
    }

    private func currentSystemAudioStatus() -> PermissionStatus {
        CGPreflightScreenCaptureAccess() ? .granted : .denied
    }
}
#endif
