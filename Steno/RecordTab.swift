import SwiftUI
import StenoKit

struct RecordTab: View {
    @EnvironmentObject private var controller: DictationController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showErrorBanner = false
    @State private var showPermissionRepair = false

    var body: some View {
        Group {
            if #available(macOS 14.0, *) {
                content
                    .onChange(of: controller.lastError) { _, _ in
                        animateErrorBannerUpdate()
                    }
                    .onChange(of: controller.hotkeyRegistrationMessage) { _, _ in
                        animateErrorBannerUpdate()
                    }
            } else {
                content
                    .onChange(of: controller.lastError) { _ in
                        animateErrorBannerUpdate()
                    }
                    .onChange(of: controller.hotkeyRegistrationMessage) { _ in
                        animateErrorBannerUpdate()
                    }
            }
        }
        .onAppear {
            showErrorBanner = hasError
        }
        .sheet(isPresented: $showPermissionRepair) {
            PermissionRepairView(onDismiss: { showPermissionRepair = false })
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            // Error/warning banner
            if showErrorBanner {
                errorBanner
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(errorBannerAccessibilityLabel)
                    .padding(.bottom, StenoDesign.md)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .move(edge: .top).combined(with: .opacity)
                    )
            }

            Spacer()

            // Mic button
            MicButton(
                isRecording: controller.isRecording,
                isTranscribing: controller.recordingLifecycleState == .transcribing,
                handsFreeOn: controller.handsFreeOn,
                onTap: { controller.toggleHandsFree() }
            )

            // Recording elapsed time
            if controller.isRecording {
                Text(formatElapsedTime(controller.recordingElapsed))
                    .font(StenoDesign.caption().monospacedDigit())
                    .foregroundStyle(StenoDesign.accent)
                    .padding(.top, StenoDesign.xs)
                    .transition(.opacity)
                    .accessibilityLabel("Recording time")
                    .accessibilityValue(formatElapsedTime(controller.recordingElapsed))
            }

            // Status text
            VStack(spacing: StenoDesign.xs) {
                Text(controller.status)
                    .font(StenoDesign.subheadline())
                    .foregroundStyle(StenoDesign.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .accessibilityLabel("Recording status")
                    .accessibilityValue(controller.status)

                if controller.recordingLifecycleState == .transcribing {
                    Text("(usually 2\u{2013}5 seconds)")
                        .font(StenoDesign.caption())
                        .foregroundStyle(StenoDesign.textSecondary)
                }
            }
            .padding(.top, StenoDesign.sm)

            // Active model indicator — so the user always knows which
            // whisper model is loaded without opening Settings.
            if let modelLabel = activeModelLabel {
                Text(modelLabel)
                    .font(StenoDesign.caption())
                    .foregroundStyle(StenoDesign.textSecondary)
                    .padding(.top, StenoDesign.xs)
                    .accessibilityLabel("Active whisper model: \(modelLabel)")
            }

            Spacer()

            // Last transcript card
            lastTranscriptCard
                .animation(
                    reduceMotion ? nil : .easeInOut(duration: StenoDesign.animationNormal),
                    value: controller.lastTranscript
                )
        }
        .padding(.vertical, StenoDesign.lg)
    }

    private func animateErrorBannerUpdate() {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: StenoDesign.animationNormal)) {
            showErrorBanner = hasError
        }
    }

    private var hasError: Bool {
        !controller.lastError.isEmpty || !controller.hotkeyRegistrationMessage.isEmpty
    }

    private var errorBannerAccessibilityLabel: String {
        var parts: [String] = []
        if !controller.hotkeyRegistrationMessage.isEmpty {
            parts.append(controller.hotkeyRegistrationMessage)
        }
        if !controller.lastError.isEmpty {
            parts.append(controller.lastError)
        }
        return parts.joined(separator: ". ")
    }

    private enum BlockedPermission {
        case accessibility
        case inputMonitoring
        case microphone
    }

    /// Resolves which permission is actually blocking — prefers concrete
    /// not-yet-granted statuses over string-matching on the error text, so
    /// the Grant button routes to the real pane, not whatever the first
    /// error message happened to mention. Falls back to message parsing
    /// only when every status is granted but a permission-flavored error
    /// is still surfacing.
    private var blockedPermission: BlockedPermission? {
        if controller.accessibilityPermissionStatus != .granted
            && bannerMentions("accessibility") {
            return .accessibility
        }
        if controller.inputMonitoringPermissionStatus != .granted
            && bannerMentions("input monitoring") {
            return .inputMonitoring
        }
        if controller.microphonePermissionStatus != .granted
            && bannerMentions("microphone") {
            return .microphone
        }
        if bannerMentions("input monitoring") { return .inputMonitoring }
        if bannerMentions("accessibility") { return .accessibility }
        if bannerMentions("microphone") { return .microphone }
        return nil
    }

    private var isPermissionRelated: Bool {
        blockedPermission != nil
    }

    private func bannerMentions(_ keyword: String) -> Bool {
        let combined = (controller.lastError + " " + controller.hotkeyRegistrationMessage).lowercased()
        return combined.contains(keyword)
    }

    private var grantLabel: String {
        switch blockedPermission {
        case .accessibility: return "Open Accessibility"
        case .inputMonitoring: return "Open Input Monitoring"
        case .microphone: return "Open Microphone"
        case .none: return "Open Settings"
        }
    }

    private func openRelevantSettings() {
        switch blockedPermission {
        case .accessibility: PermissionDiagnostics.openAccessibilitySettings()
        case .inputMonitoring: PermissionDiagnostics.openInputMonitoringSettings()
        case .microphone: PermissionDiagnostics.openMicrophoneSettings()
        case .none: PermissionDiagnostics.openAccessibilitySettings()
        }
    }

    /// Detects the "granted but macOS hasn't propagated to this process yet"
    /// state: user has toggled the pane on, but the hotkey tap still can't
    /// install. This happens because TCC caches per-process decisions until
    /// relaunch. When we detect it, surface a Restart button so the user
    /// doesn't have to guess.
    private var needsRestart: Bool {
        guard !controller.hotkeyRegistrationMessage.isEmpty else { return false }
        let msg = controller.hotkeyRegistrationMessage.lowercased()
        guard msg.contains("accessibility") || msg.contains("permission") else {
            return false
        }
        return controller.accessibilityPermissionStatus == .granted
    }

    private func restartApp() {
        let bundlePath = Bundle.main.bundleURL.path
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = ["-n", bundlePath]
        try? task.run()
        NSApp.terminate(nil)
    }

    /// Collapses the two possible error sources (hotkey registration and
    /// last runtime error) into a single short line for the pill banner.
    /// If both are set, the hotkey message wins because it is usually the
    /// blocking one; full detail is always available in Settings →
    /// Diagnostics.
    private var compactErrorText: String {
        if needsRestart {
            return "Permission granted — restart Lisan to activate."
        }
        if !controller.hotkeyRegistrationMessage.isEmpty {
            return controller.hotkeyRegistrationMessage
        }
        return controller.lastError
    }

    private var errorBanner: some View {
        // Compact single-line pill. Previous design had a full-height red bar
        // and a VStack that blew up for multi-message states, making the banner
        // dominate the Record tab even when the message was a one-liner
        // permission prompt. This version stays ~32pt tall and reads left→right:
        // icon · message · action · dismiss.
        HStack(spacing: StenoDesign.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(StenoDesign.caption())
                .foregroundStyle(StenoDesign.error)

            Text(compactErrorText)
                .font(StenoDesign.caption())
                .foregroundStyle(StenoDesign.error)
                .lineLimit(1)
                .truncationMode(.tail)

            if needsRestart {
                Button("Restart Lisan") {
                    restartApp()
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .accessibilityLabel("Restart Lisan to apply granted permissions")
            } else if isPermissionRelated {
                Button("Fix permissions") {
                    showPermissionRepair = true
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .accessibilityLabel("Open permission repair flow")
            }

            Spacer(minLength: StenoDesign.xs)

            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: StenoDesign.animationNormal)) {
                    controller.clearErrors()
                    showErrorBanner = false
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(StenoDesign.caption())
                    .foregroundStyle(StenoDesign.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, StenoDesign.sm)
        .padding(.vertical, StenoDesign.xs)
        .background(StenoDesign.errorBackground)
        .clipShape(Capsule())
        .overlay(
            Capsule().stroke(StenoDesign.errorBorder, lineWidth: 1)
        )
    }

    private var lastTranscriptCard: some View {
        VStack(alignment: .leading, spacing: StenoDesign.sm) {
            HStack {
                Text("Last Transcript")
                    .font(StenoDesign.bodyEmphasis())
                    .foregroundStyle(StenoDesign.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if !controller.lastTranscript.isEmpty {
                    CopyButtonView(action: {
                        if let entry = controller.recentEntries.first {
                            controller.copyEntry(entry)
                        }
                    }, label: "Copy last transcript")

                    Button {
                        controller.pasteLastTranscript()
                    } label: {
                        Image(systemName: "doc.on.clipboard.fill")
                            .font(StenoDesign.caption())
                            .foregroundStyle(StenoDesign.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .help("Paste")
                    .accessibilityLabel("Paste last transcript")
                }
            }

            if controller.lastTranscript.isEmpty {
                Text(emptyStateHint)
                    .font(StenoDesign.body())
                    .foregroundStyle(StenoDesign.textSecondary)
            } else {
                Text(controller.lastTranscript)
                    .font(StenoDesign.body())
                    .foregroundStyle(StenoDesign.textPrimary)
                    .lineLimit(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .cardStyle()
    }

    private var activeModelLabel: String? {
        let path = controller.preferences.dictation.modelPath
        guard !path.isEmpty else { return nil }
        if let entry = WhisperModelCatalog.entry(forModelPath: path) {
            return "Model: \(entry.displayName) · \(entry.sizeLabel)"
        }
        let filename = (path as NSString).lastPathComponent
        return filename.isEmpty ? nil : "Model: \(filename)"
    }

    private var emptyStateHint: String {
        if controller.microphonePermissionStatus == .denied {
            return "Microphone access denied. Grant access in Settings to start dictating."
        }
        if controller.microphonePermissionStatus == .unknown {
            return "Grant microphone access to start dictating."
        }

        let hotkeys = controller.preferences.hotkeys
        if hotkeys.optionPressToTalkEnabled {
            if let keyCode = hotkeys.handsFreeGlobalKeyCode {
                return "Hold Option to dictate, or press \(keyLabel(for: keyCode)) for hands-free"
            }
            return "Hold Option to start dictating"
        }
        if let keyCode = hotkeys.handsFreeGlobalKeyCode {
            return "Press \(keyLabel(for: keyCode)) to start hands-free dictation"
        }
        return "Configure a hotkey in Settings to start dictating"
    }

    private func keyLabel(for keyCode: UInt16) -> String {
        switch keyCode {
        case 122: return "F1"
        case 120: return "F2"
        case 160: return "F3"
        case 131: return "F4"
        case 96:  return "F5"
        case 97:  return "F6"
        case 98:  return "F7"
        case 100: return "F8"
        case 101: return "F9"
        case 109: return "F10"
        case 103: return "F11"
        case 111: return "F12"
        case 105: return "F13"
        case 107: return "F14"
        case 113: return "F15"
        case 106: return "F16"
        case 64:  return "F17"
        case 79:  return "F18"
        case 80:  return "F19"
        case 90:  return "F20"
        default: return "F\(keyCode)"
        }
    }

    private func formatElapsedTime(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
