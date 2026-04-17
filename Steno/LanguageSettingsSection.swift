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

                Divider()

                Text("Vocabulary file")
                    .font(StenoDesign.bodyEmphasis())

                TextField(
                    "Path to vocabulary.txt (one phrase per line)",
                    text: $preferences.dictation.vocabularyFilePath
                )
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .truncationMode(.middle)

                if !preferences.dictation.vocabularyFilePath.isEmpty {
                    let fileExists = FileManager.default.fileExists(atPath: preferences.dictation.vocabularyFilePath)
                    HStack(spacing: StenoDesign.xs) {
                        Image(systemName: fileExists ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .font(StenoDesign.caption())
                        Text(fileExists ? "File found" : "File not found")
                            .font(StenoDesign.caption())
                    }
                    .foregroundStyle(fileExists ? StenoDesign.success : StenoDesign.warning)
                }

                Text("Add client names, brand names, Arabic proper nouns, or transliterations — one phrase per line. The engine uses these to bias recognition.")
                    .font(StenoDesign.caption())
                    .foregroundStyle(StenoDesign.textSecondary)
            }
        }
    }

    private var languageDescription: String {
        switch preferences.dictation.languageMode {
        case .en:
            return "English-only dictation. Best accuracy for English audio."
        case .ar:
            return "Arabic-only dictation. Best accuracy for Arabic audio."
        case .auto:
            return "Auto-detects the spoken language. Slightly lower accuracy than explicit mode."
        }
    }
}
