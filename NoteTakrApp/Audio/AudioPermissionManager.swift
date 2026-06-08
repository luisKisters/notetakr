// Permission state manager for microphone and system-audio (screen recording) access.
// Verified only on the macOS CI runner / physical Mac.
#if canImport(AVFoundation)
import AVFoundation
import AppKit
import Foundation
import NoteTakrCore
#if canImport(EventKit)
import EventKit
#endif

@MainActor
final class AudioPermissionManager: ObservableObject {
    @Published private(set) var microphoneStatus: PermissionStatus = .notDetermined
    @Published private(set) var systemAudioStatus: PermissionStatus = .notDetermined
    @Published private(set) var calendarStatus: PermissionStatus = .notDetermined
    @Published private(set) var systemAudioRestartRequired = false

#if canImport(EventKit)
    private let eventStore = EKEventStore()
#endif

    init() {
        refresh()
    }

    func refresh() {
        microphoneStatus = currentMicrophoneStatus()
        systemAudioStatus = currentSystemAudioStatus()
        if systemAudioStatus == .granted {
            systemAudioRestartRequired = false
        }
        calendarStatus = currentCalendarStatus()
    }

    func requestMicrophoneAccess() async {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        microphoneStatus = granted ? currentMicrophoneStatus() : .denied
    }

    /// Opens the screen recording permission pane in System Settings.
    /// Screen recording permission is required for system-audio capture via ScreenCaptureKit.
    func requestSystemAudioAccess() {
        let granted = CGRequestScreenCaptureAccess()
        systemAudioStatus = currentSystemAudioStatus()
        systemAudioRestartRequired = granted && systemAudioStatus != .granted
        if !granted {
            openScreenRecordingSettings()
        }
        scheduleScreenCaptureRefreshes()
    }

    func restartApp() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            "sleep 0.5; open \"$1\"",
            "relaunch",
            Bundle.main.bundlePath
        ]
        try? process.run()
        NSApp.terminate(nil)
    }

    func requestCalendarAccess() async {
#if canImport(EventKit)
        do {
            let granted: Bool
            if #available(macOS 14.0, *) {
                granted = try await eventStore.requestFullAccessToEvents()
            } else {
                granted = await withCheckedContinuation { continuation in
                    eventStore.requestAccess(to: .event) { result, _ in
                        continuation.resume(returning: result)
                    }
                }
            }
            calendarStatus = granted ? currentCalendarStatus() : .denied
        } catch {
            calendarStatus = currentCalendarStatus()
        }
#else
        calendarStatus = .denied
#endif
    }

    private func currentMicrophoneStatus() -> PermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return .granted
        case .denied, .restricted: return .denied
        default: return .notDetermined
        }
    }

    private func currentSystemAudioStatus() -> PermissionStatus {
        // CGPreflightScreenCaptureAccess returns false for both undetermined and denied;
        // default to .notDetermined since we cannot distinguish them here.
        CGPreflightScreenCaptureAccess() ? .granted : .notDetermined
    }

    private func currentCalendarStatus() -> PermissionStatus {
#if canImport(EventKit)
        let status = EKEventStore.authorizationStatus(for: .event)
        if #available(macOS 14.0, *) {
            switch status {
            case .fullAccess: return .granted
            case .writeOnly, .denied, .restricted: return .denied
            case .notDetermined: return .notDetermined
            @unknown default: return .denied
            }
        } else {
            switch status {
            case .authorized: return .granted
            case .denied, .restricted: return .denied
            case .notDetermined: return .notDetermined
            @unknown default: return .denied
            }
        }
#else
        return .denied
#endif
    }

    private func scheduleScreenCaptureRefreshes() {
        let delays: [UInt64] = [
            500_000_000,
            2_000_000_000,
            5_000_000_000
        ]

        for delay in delays {
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: delay)
                await MainActor.run {
                    self?.refresh()
                }
            }
        }
    }

    private func openScreenRecordingSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
#endif
