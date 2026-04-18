import SwiftUI

struct GeneralSettingsSection: View {
    @Binding var preferences: AppPreferences
    let launchAtLoginWarning: String

    var body: some View {
        settingsCard("General") {
            Toggle("Launch at login", isOn: $preferences.general.launchAtLoginEnabled)
            Toggle("Show Dock icon", isOn: $preferences.general.showDockIcon)
            Toggle("Show onboarding on next launch", isOn: $preferences.general.showOnboarding)
            if !launchAtLoginWarning.isEmpty {
                Text(launchAtLoginWarning)
                    .font(StenoDesign.caption())
                    .foregroundStyle(StenoDesign.error)
            }
            Button("Re-run onboarding wizard") {
                preferences.general.showOnboarding = true
            }
            .buttonStyle(.bordered)

            Divider()

            VStack(alignment: .leading, spacing: StenoDesign.xs) {
                Toggle("Save transcript history to disk", isOn: $preferences.general.persistHistoryOnDisk)
                Text("When off, transcripts live only in this app session and disappear at quit. When on, they're kept in ~/Library/Application Support/Steno/transcript-history.json with owner-only permissions (0600) and excluded from iCloud/Time Machine backup.")
                    .font(StenoDesign.caption())
                    .foregroundStyle(StenoDesign.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if preferences.general.persistHistoryOnDisk {
                    Stepper(
                        value: $preferences.general.historyRetentionDays,
                        in: 1...365
                    ) {
                        Text("Keep for \(preferences.general.historyRetentionDays) day\(preferences.general.historyRetentionDays == 1 ? "" : "s")")
                    }
                    Text("Entries older than this are pruned from both memory and the on-disk file on every new transcription.")
                        .font(StenoDesign.caption())
                        .foregroundStyle(StenoDesign.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    // Destructive-change warning: pruning is permanent.
                    // No undo is possible because we don't keep tombstones
                    // of deleted entries — they're just gone.
                    HStack(alignment: .top, spacing: StenoDesign.xs) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(StenoDesign.warning)
                            .font(StenoDesign.caption())
                        Text("Shortening this window permanently deletes entries older than the new window. Pruning cannot be undone.")
                            .font(StenoDesign.caption())
                            .foregroundStyle(StenoDesign.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}
