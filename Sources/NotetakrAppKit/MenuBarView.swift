#if os(macOS)
import SwiftUI
import NotetakrCore

/// Contents of the menu-bar popover.
///
/// Task 0 shows only the app header and a placeholder Start/Stop Recording
/// button. Today view, sessions, and settings are added in later tasks.
public struct MenuBarView: View {
    @Bindable private var model: AppModel

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(AppInfo.name)
                    .font(.headline)
                Text(AppInfo.tagline)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Button(action: model.toggleRecording) {
                Label(model.primaryActionTitle,
                      systemImage: model.isRecording ? "stop.circle.fill" : "record.circle")
            }
            .accessibilityIdentifier("primary-record-button")

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .accessibilityIdentifier("quit-button")
        }
        .padding(12)
        .frame(width: 260)
    }
}
#endif
