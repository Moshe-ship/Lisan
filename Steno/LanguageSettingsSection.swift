import SwiftUI
import StenoKit

struct LanguageSettingsSection: View {
    @Binding var preferences: AppPreferences

    var body: some View {
        settingsCard("Language") {
            VStack(alignment: .leading, spacing: StenoDesign.sm) {
                Text("Dictation language")
                    .font(StenoDesign.bodyEmphasis())

                Picker("", selection: $preferences.dictation.languageMode) {
                    ForEach(LanguageMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Text(languageDescription)
                    .font(StenoDesign.caption())
                    .foregroundStyle(StenoDesign.textSecondary)

                HStack(alignment: .top, spacing: StenoDesign.xs) {
                    Image(systemName: "info.circle")
                        .font(StenoDesign.caption())
                        .foregroundStyle(StenoDesign.textSecondary)
                    Text("Auto picks one language per recording, not per word — whisper.cpp does not code-switch. For mixed speech, hold a pure phrase in one language at a time.")
                        .font(StenoDesign.caption())
                        .foregroundStyle(StenoDesign.textSecondary)
                }

                if preferences.dictation.languageMode == .auto {
                    Toggle(isOn: $preferences.dictation.twoPassAutoDetect) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Accurate auto-detect (slower)")
                                .font(StenoDesign.body())
                            Text("Runs a short whisper -dl preflight before each transcription. Fixes the English-bias whisper shows on short Arabic clips, at ~300-500ms extra latency per dictation. Recommended if Auto keeps picking English for your Arabic.")
                                .font(StenoDesign.caption())
                                .foregroundStyle(StenoDesign.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                Divider()

                VocabularyPackPicker(preferences: $preferences)

                DisclosureGroup("Custom vocabulary file") {
                    VStack(alignment: .leading, spacing: StenoDesign.xs) {
                        TextField(
                            "Path to vocabulary.txt or packs directory",
                            text: $preferences.dictation.vocabularyFilePath
                        )
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.caption, design: .monospaced))
                        .truncationMode(.middle)

                        if !preferences.dictation.vocabularyFilePath.isEmpty {
                            let fileExists = FileManager.default.fileExists(atPath: preferences.dictation.vocabularyFilePath)
                            HStack(spacing: StenoDesign.xs) {
                                Image(systemName: fileExists ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                    .font(StenoDesign.caption())
                                Text(fileExists ? "Path found" : "Path not found")
                                    .font(StenoDesign.caption())
                            }
                            .foregroundStyle(fileExists ? StenoDesign.success : StenoDesign.warning)
                        }

                        Text("Point at a single .txt (one phrase per line) or at a directory — all .txt files in a directory are loaded together.")
                            .font(StenoDesign.caption())
                            .foregroundStyle(StenoDesign.textSecondary)
                    }
                    .padding(.top, StenoDesign.xs)
                }
                .font(StenoDesign.caption())
                .foregroundStyle(StenoDesign.textSecondary)
            }
        }
    }

    private var languageDescription: String {
        switch preferences.dictation.languageMode {
        case .en:
            return "Forces English. Best for English-only speech. Arabic audio in this mode will produce garbage output."
        case .ar:
            return "Forces Arabic. Best for Arabic-only speech. English audio in this mode will produce garbage output."
        case .auto:
            return "Recommended for bilingual or mixed speech. Slightly lower per-language accuracy than forcing a single language."
        }
    }
}
