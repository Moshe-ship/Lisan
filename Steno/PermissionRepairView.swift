import SwiftUI
import StenoKit

/// Single-screen permission repair flow. Shown from the Record tab when
/// any of the three required permissions is not granted. Diagnoses each
/// permission explicitly, routes each Grant button to the correct System
/// Settings pane, and surfaces the "restart required" state when a grant
/// is registered but the hotkey tap still can't install.
///
/// Designed to be idiot-proof — no jargon, no composite messages, no
/// "permission required" banners that don't say which one.
struct PermissionRepairView: View {
    @EnvironmentObject private var controller: DictationController
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: StenoDesign.md) {
            header

            Divider()

            permissionRow(
                title: "Microphone",
                description: "Captures audio when you hold Option.",
                status: controller.microphonePermissionStatus,
                primaryAction: { PermissionDiagnostics.openMicrophoneSettings() },
                primaryLabel: "Open Microphone settings",
                requestAction: {
                    Task { await controller.requestMicrophonePermission() }
                }
            )

            permissionRow(
                title: "Accessibility",
                description: "Lets Lisan type or paste transcribed text into the app you're using, and register the global Option press-to-talk hotkey.",
                status: controller.accessibilityPermissionStatus,
                primaryAction: { PermissionDiagnostics.openAccessibilitySettings() },
                primaryLabel: "Open Accessibility settings",
                requestAction: {
                    _ = controller.requestAccessibilityPermission()
                }
            )

            permissionRow(
                title: "Input Monitoring",
                description: "Lets Lisan detect the global hotkey while another app is focused.",
                status: controller.inputMonitoringPermissionStatus,
                primaryAction: { PermissionDiagnostics.openInputMonitoringSettings() },
                primaryLabel: "Open Input Monitoring settings",
                requestAction: {
                    _ = controller.requestInputMonitoringPermission()
                }
            )

            if needsRestart {
                restartCallout
            }

            Spacer(minLength: 0)

            footer
        }
        .padding(StenoDesign.lg)
        .frame(minWidth: 520, idealWidth: 600, minHeight: 440, idealHeight: 540)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: StenoDesign.xs) {
            Text("Permission repair")
                .font(StenoDesign.heading2())
            Text("Grant the three permissions below to unblock dictation. Each button jumps straight to the right pane in System Settings. Lisan re-checks state automatically when you come back.")
                .font(StenoDesign.caption())
                .foregroundStyle(StenoDesign.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Bundle path: \(PermissionDiagnostics.currentAppBundlePath())")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(StenoDesign.textSecondary)
                .textSelection(.enabled)
            Button("Reveal Lisan.app in Finder") {
                PermissionDiagnostics.revealCurrentAppInFinder()
            }
            .buttonStyle(.plain)
            .font(StenoDesign.caption())
            .foregroundStyle(StenoDesign.accent)
            .accessibilityHint("If the app isn't listed in the pane, drag Lisan.app from Finder into the list.")
        }
    }

    @ViewBuilder
    private func permissionRow(
        title: String,
        description: String,
        status: PermissionDiagnostics.AccessStatus,
        primaryAction: @escaping () -> Void,
        primaryLabel: String,
        requestAction: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: StenoDesign.md) {
            statusBadge(status)
                .frame(width: 72, alignment: .leading)

            VStack(alignment: .leading, spacing: StenoDesign.xs) {
                Text(title)
                    .font(StenoDesign.bodyEmphasis())
                Text(description)
                    .font(StenoDesign.caption())
                    .foregroundStyle(StenoDesign.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: StenoDesign.xs) {
                    if status != .granted {
                        Button(primaryLabel, action: primaryAction)
                            .buttonStyle(.borderedProminent)
                            .tint(StenoDesign.accent)
                            .controlSize(.small)

                        if status == .unknown {
                            Button("Ask now", action: requestAction)
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                    } else {
                        Text("Nothing to do here.")
                            .font(StenoDesign.caption())
                            .foregroundStyle(StenoDesign.textSecondary)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(StenoDesign.sm)
        .background(StenoDesign.surface)
        .cornerRadius(StenoDesign.radiusSmall)
    }

    private func statusBadge(_ status: PermissionDiagnostics.AccessStatus) -> some View {
        let (label, color, icon): (String, Color, String) = {
            switch status {
            case .granted:
                return ("Granted", StenoDesign.success, "checkmark.circle.fill")
            case .denied:
                return ("Blocked", StenoDesign.error, "xmark.circle.fill")
            case .unknown:
                return ("Not yet asked", StenoDesign.warning, "questionmark.circle.fill")
            }
        }()
        return HStack(spacing: StenoDesign.xs) {
            Image(systemName: icon).foregroundStyle(color)
            Text(label)
                .font(StenoDesign.captionEmphasis())
                .foregroundStyle(color)
        }
    }

    private var needsRestart: Bool {
        guard !controller.hotkeyRegistrationMessage.isEmpty else { return false }
        let msg = controller.hotkeyRegistrationMessage.lowercased()
        guard msg.contains("accessibility") || msg.contains("permission") else {
            return false
        }
        return controller.accessibilityPermissionStatus == .granted
    }

    private var restartCallout: some View {
        HStack(alignment: .top, spacing: StenoDesign.sm) {
            Image(systemName: "arrow.clockwise.circle.fill")
                .foregroundStyle(StenoDesign.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text("Relaunch required")
                    .font(StenoDesign.bodyEmphasis())
                Text("Accessibility looks granted, but macOS has cached the old denial for this running process. Relaunch Lisan to pick up the new permission.")
                    .font(StenoDesign.caption())
                    .foregroundStyle(StenoDesign.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button("Relaunch Lisan") { restartApp() }
                .buttonStyle(.borderedProminent)
                .tint(StenoDesign.accent)
                .controlSize(.small)
        }
        .padding(StenoDesign.sm)
        .background(StenoDesign.surface)
        .cornerRadius(StenoDesign.radiusSmall)
    }

    private var footer: some View {
        HStack {
            Text(allGranted
                 ? "All permissions granted. You're ready to dictate."
                 : "Blocked: \(blockedCount) of 3")
                .font(StenoDesign.caption())
                .foregroundStyle(allGranted ? StenoDesign.success : StenoDesign.textSecondary)
            Spacer()
            Button("Done", action: onDismiss)
                .buttonStyle(.borderedProminent)
                .tint(StenoDesign.accent)
                .disabled(!allGranted && !mayDismissBlocked)
        }
    }

    private var allGranted: Bool {
        controller.microphonePermissionStatus == .granted
            && controller.accessibilityPermissionStatus == .granted
            && controller.inputMonitoringPermissionStatus == .granted
    }

    /// Allow dismissal even when some are still missing — the user may be
    /// intentionally deferring. We just say so in the footer.
    private var mayDismissBlocked: Bool { true }

    private var blockedCount: Int {
        var n = 0
        if controller.microphonePermissionStatus != .granted { n += 1 }
        if controller.accessibilityPermissionStatus != .granted { n += 1 }
        if controller.inputMonitoringPermissionStatus != .granted { n += 1 }
        return n
    }

    private func restartApp() {
        let bundlePath = Bundle.main.bundleURL.path
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = ["-n", bundlePath]
        try? task.run()
        NSApp.terminate(nil)
    }
}
