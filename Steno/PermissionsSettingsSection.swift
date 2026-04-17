import SwiftUI

struct PermissionsSettingsSection: View {
    @EnvironmentObject private var controller: DictationController

    var body: some View {
        settingsCard("Permissions") {
            PermissionStatusCard(
                title: "Microphone",
                description: "Required to capture audio for transcription.",
                status: controller.microphonePermissionStatus,
                onRequest: { controller.requestMicrophonePermission() },
                onOpenSettings: { controller.openMicrophoneSettings() }
            )

            PermissionStatusCard(
                title: "Accessibility",
                description: "Lets Lisan type or paste into the app you're using.",
                status: controller.accessibilityPermissionStatus,
                onRequest: { controller.requestAccessibilityPermission() },
                onOpenSettings: { controller.openAccessibilitySettings() }
            )

            PermissionStatusCard(
                title: "Input Monitoring",
                description: "Lets Lisan detect global hotkeys while other apps are focused.",
                status: controller.inputMonitoringPermissionStatus,
                onRequest: { controller.requestInputMonitoringPermission() },
                onOpenSettings: { controller.openInputMonitoringSettings() }
            )
        }
    }
}
