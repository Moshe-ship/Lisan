import SwiftUI
import StenoKit

struct SettingsView: View {
    @EnvironmentObject private var controller: DictationController
    @State private var preferencesDraft: AppPreferences = .default
    @State private var savedConfirmationVisible = false
    @State private var savedConfirmationTask: Task<Void, Never>?

    private var isDirty: Bool {
        preferencesDraft != controller.preferences
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: StenoDesign.lg) {
                PermissionsSettingsSection()
                RecordingSettingsSection(
                    preferences: $preferencesDraft,
                    hotkeyRegistrationMessage: controller.hotkeyRegistrationMessage
                )
                EngineSettingsSection(
                    preferences: $preferencesDraft,
                    controller: controller
                )
                LanguageSettingsSection(preferences: $preferencesDraft)
                ArabicSettingsSection(preferences: $preferencesDraft)
                InsertionSettingsSection(preferences: $preferencesDraft)
                MediaSettingsSection(preferences: $preferencesDraft)
                LexiconSettingsSection(preferences: $preferencesDraft)
                CleanupStyleSettingsSection(preferences: $preferencesDraft)
                SnippetsSettingsSection(preferences: $preferencesDraft)
                GeneralSettingsSection(
                    preferences: $preferencesDraft,
                    launchAtLoginWarning: controller.launchAtLoginWarning
                )
                DiagnosticsSettingsSection(telemetry: controller.telemetry)

                // Bottom actions
                VStack(spacing: StenoDesign.md) {
                    Divider()

                    HStack(spacing: StenoDesign.sm) {
                        Button(isDirty ? "Save & Apply" : "Saved") {
                            controller.applySettingsDraft(preferences: preferencesDraft)
                            triggerSavedConfirmation()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(StenoDesign.accent)
                        .disabled(!isDirty && !savedConfirmationVisible)

                        if savedConfirmationVisible {
                            HStack(spacing: StenoDesign.xs) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(StenoDesign.accent)
                                Text("Saved")
                                    .font(StenoDesign.caption())
                                    .foregroundStyle(StenoDesign.textSecondary)
                            }
                            .transition(.opacity)
                            .accessibilityLabel("Settings saved")
                        } else if isDirty {
                            Text("Unsaved changes")
                                .font(StenoDesign.caption())
                                .foregroundStyle(StenoDesign.textSecondary)
                                .transition(.opacity)
                        }

                        Spacer()
                    }
                }
                .padding(.top, StenoDesign.sm)
            }
            .padding(.vertical, StenoDesign.lg)
        }
        .onAppear {
            preferencesDraft = controller.preferences
        }
    }

    private func triggerSavedConfirmation() {
        savedConfirmationTask?.cancel()
        withAnimation(.easeInOut(duration: StenoDesign.animationNormal)) {
            savedConfirmationVisible = true
        }
        savedConfirmationTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: StenoDesign.animationNormal)) {
                savedConfirmationVisible = false
            }
        }
    }
}
