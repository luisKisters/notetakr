import SwiftUI
import NoteTakrCore

struct SettingsView: View {
    @StateObject private var permissions = AudioPermissionManager()

    var body: some View {
        Form {
            Section("Permissions") {
                permissionRow(
                    label: "Microphone",
                    detail: "Required for recording your voice",
                    status: permissions.microphoneStatus,
                    action: {
                        Task { await permissions.requestMicrophoneAccess() }
                    }
                )
                permissionRow(
                    label: "System Audio",
                    detail: "Requires Screen Recording permission (ScreenCaptureKit)",
                    status: permissions.systemAudioStatus,
                    action: {
                        permissions.requestSystemAudioAccess()
                    }
                )
            }

            Section {
                Button("Refresh Status") {
                    permissions.refresh()
                }
                .accessibilityIdentifier("refreshPermissionsButton")
            }

            Section {
                Text("System audio capture requires Screen Recording permission in System Settings › Privacy & Security.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("systemAudioNote")
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 380, minHeight: 260)
        .onAppear { permissions.refresh() }
    }

    @ViewBuilder
    private func permissionRow(
        label: String,
        detail: String,
        status: PermissionStatus,
        action: @escaping () -> Void
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .fontWeight(.medium)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if status != .granted {
                Button("Grant Access", action: action)
                    .controlSize(.small)
                    .accessibilityIdentifier("grantAccess_\(label)")
            }
            statusBadge(status)
        }
        .padding(.vertical, 2)
        .accessibilityIdentifier("permissionRow_\(label)")
    }

    @ViewBuilder
    private func statusBadge(_ status: PermissionStatus) -> some View {
        let (label, color): (String, Color) = switch status {
        case .granted: ("Granted", .green)
        case .denied: ("Denied", .red)
        case .notDetermined: ("Not Set", .orange)
        }
        Text(label)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
            .accessibilityIdentifier("permissionStatus_\(status.rawValue)")
    }
}
