import SwiftUI
import StenoKit

struct ArabicSettingsSection: View {
    @Binding var preferences: AppPreferences

    /// Demo sentence that exercises every transform. Used for the live preview.
    /// Contains harakat, tatweel, hamza-on-alef, ya maqsura, ta marbuta, waw
    /// hamza, Arabic-Indic digits, ASCII comma, ASCII question mark — so users
    /// can see exactly what their settings do.
    private static let previewSample = "أَحْمَد ذَهَبَ إلى المَدْرَسَـة في عَام ٢٠٢٦, مَسْؤُول. كيف حالك?"

    var body: some View {
        settingsCard("Arabic") {
            VStack(alignment: .leading, spacing: StenoDesign.sm) {

                // Master switch
                Toggle(isOn: $preferences.dictation.bilingualCleanupEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Arabic-aware cleanup")
                            .font(StenoDesign.bodyEmphasis())
                        Text("Splits bilingual transcripts and runs Arabic normalization on Arabic sentences. Zero overhead for English-only speech.")
                            .font(StenoDesign.caption())
                            .foregroundStyle(StenoDesign.textSecondary)
                    }
                }

                if preferences.dictation.bilingualCleanupEnabled {
                    Divider()

                    // Live preview
                    VStack(alignment: .leading, spacing: StenoDesign.xs) {
                        Text("Live preview")
                            .font(StenoDesign.caption())
                            .foregroundStyle(StenoDesign.textSecondary)
                            .textCase(.uppercase)

                        Text(Self.previewSample)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(StenoDesign.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .environment(\.layoutDirection, .rightToLeft)

                        Image(systemName: "arrow.down")
                            .font(StenoDesign.caption())
                            .foregroundStyle(StenoDesign.textSecondary)
                            .frame(maxWidth: .infinity)

                        Text(previewedOutput)
                            .font(.system(.body, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .environment(\.layoutDirection, .rightToLeft)
                    }
                    .padding(StenoDesign.sm)
                    .background(StenoDesign.surfaceSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                    Divider()

                    // Safe defaults (minimal, correctness-preserving)
                    Text("Always-safe transforms")
                        .font(StenoDesign.bodyEmphasis())

                    arabicToggle(
                        "Strip diacritics (harakat)",
                        description: "Remove fatḥa, kasra, ḍamma, sukūn, shadda, tanwīn. Whisper rarely emits them correctly anyway.",
                        isOn: $preferences.dictation.arabicOptions.stripHarakat
                    )

                    arabicToggle(
                        "Strip tatweel (ـ)",
                        description: "Remove decorative kashida elongation. Typographic only — no semantic meaning.",
                        isOn: $preferences.dictation.arabicOptions.stripTatweel
                    )

                    arabicToggle(
                        "Unify hamza-on-alef (أ إ آ → ا)",
                        description: "Whisper often guesses the wrong hamza. Unifying avoids wrong-spelling artifacts.",
                        isOn: $preferences.dictation.arabicOptions.unifyAlef
                    )

                    arabicToggle(
                        "Convert ASCII punctuation (, ; ?) to Arabic (، ؛ ؟)",
                        description: "Whisper emits Latin punctuation for Arabic. This replaces them inside Arabic sentences only — English sentences keep ASCII.",
                        isOn: $preferences.dictation.arabicPunctuationEnabled
                    )

                    Divider()

                    // Advanced (change meaning)
                    Text("Advanced transforms")
                        .font(StenoDesign.bodyEmphasis())
                    Text("These change word meaning. Only enable if your dialect needs them.")
                        .font(StenoDesign.caption())
                        .foregroundStyle(StenoDesign.textSecondary)

                    arabicToggle(
                        "Unify ya (ى ئ → ي)",
                        description: "Collapses ya maqsura and ya with hamza. Useful for search-style text; changes meaning in MSA (على vs علي).",
                        isOn: $preferences.dictation.arabicOptions.unifyYa
                    )

                    arabicToggle(
                        "Fold teh marbuta (ة → ه)",
                        description: "Common in Egyptian / Levantine colloquial text. Wrong in MSA.",
                        isOn: $preferences.dictation.arabicOptions.foldTaMarbuta
                    )

                    arabicToggle(
                        "Fold waw-with-hamza (ؤ → و)",
                        description: "Changes spelling: مسؤول → مسوول. Use with intent.",
                        isOn: $preferences.dictation.arabicOptions.foldWawHamza
                    )

                    Divider()

                    // Digits
                    Text("Digits")
                        .font(StenoDesign.bodyEmphasis())

                    Picker("Digits", selection: digitMode) {
                        Text("Leave as-is").tag(DigitMode.asIs)
                        Text("Arabic-Indic ٠-٩").tag(DigitMode.arabic)
                        Text("ASCII 0-9").tag(DigitMode.ascii)
                    }
                    .pickerStyle(.segmented)

                    Text(digitDescription)
                        .font(StenoDesign.caption())
                        .foregroundStyle(StenoDesign.textSecondary)
                }
            }
        }
    }

    // MARK: - Helpers

    private func arabicToggle(
        _ title: String,
        description: String,
        isOn: Binding<Bool>
    ) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(description)
                    .font(StenoDesign.caption())
                    .foregroundStyle(StenoDesign.textSecondary)
            }
        }
    }

    /// Computed from options; toggling switches the two booleans correctly
    /// so they're mutually exclusive.
    private var digitMode: Binding<DigitMode> {
        Binding(
            get: {
                let opts = preferences.dictation.arabicOptions
                if opts.digitsToArabic { return .arabic }
                if opts.digitsToAscii { return .ascii }
                return .asIs
            },
            set: { newValue in
                switch newValue {
                case .asIs:
                    preferences.dictation.arabicOptions.digitsToArabic = false
                    preferences.dictation.arabicOptions.digitsToAscii = false
                case .arabic:
                    preferences.dictation.arabicOptions.digitsToArabic = true
                    preferences.dictation.arabicOptions.digitsToAscii = false
                case .ascii:
                    preferences.dictation.arabicOptions.digitsToArabic = false
                    preferences.dictation.arabicOptions.digitsToAscii = true
                }
            }
        )
    }

    private var digitDescription: String {
        switch digitMode.wrappedValue {
        case .asIs:   return "Leave digits in whatever script Whisper produced."
        case .arabic: return "Convert 0-9 → ٠-٩. Consistent Arabic prose."
        case .ascii:  return "Convert ٠-٩ and Persian digits → 0-9. Good for mixed text with prices, dates, IDs."
        }
    }

    private var previewedOutput: String {
        let opts = preferences.dictation.arabicOptions
        let normalizer = ArabicNormalizer(options: opts)
        let normalized = normalizer.normalize(Self.previewSample)
        guard preferences.dictation.arabicPunctuationEnabled else { return normalized }
        return ArabicPunctuator().punctuate(normalized)
    }

    enum DigitMode: Hashable {
        case asIs
        case arabic
        case ascii
    }
}
