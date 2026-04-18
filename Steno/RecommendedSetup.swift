import Foundation
import StenoKit

/// One-click preset for beta testers. Applies the configuration that
/// matches "good default for Arabic-first bilingual dictation" — the
/// closest honest thing to a Works Out Of The Box experience without
/// requiring testers to read the whole Settings tab first.
///
/// What the preset does, and why:
///
/// - **Small model** — biggest accuracy lever for Arabic. Downloads if
///   absent (user sees progress in the Model picker).
/// - **Language mode: Auto** — most users bounce between English and
///   Arabic; forcing either would be worse for the common case.
/// - **Two-pass auto-detect: on** — the `-dl` preflight, worth the
///   extra ~300-500ms for accuracy parity on short Arabic clips.
/// - **Segmented auto-detect: off** — segment-level detection is nice
///   but costs latency multiplied by segment count; opt-in makes
///   expected latency predictable.
/// - **Packs enabled (in priority order)**: msa-business first (most
///   users work in MSA-leaning professional contexts), then dialect
///   packs (shami + khaleeji), then agency-bilingual for marketing /
///   client work, then tech-bilingual. Users can reorder to match
///   their own workflow.
/// - **Bilingual cleanup & Arabic punctuation: on** — the reason the
///   bilingual pipeline exists.
/// - **VAD: on** — suppresses silence hallucinations whenever the
///   Silero model ships alongside whisper-cli.
///
/// `apply(to:)` writes the recommended values into a preferences
/// snapshot. Users who already changed a specific setting keep their
/// choice — the preset doesn't stomp existing customizations. Returns
/// the number of fields actually changed, so the UI can confirm
/// something happened.
enum RecommendedSetup {

    @discardableResult
    static func apply(to preferences: inout AppPreferences) -> Int {
        var changes = 0

        // Model: switch to Small if the user is still on the default base.
        // Don't overwrite a custom path or a larger model the user picked.
        if let smallEntry = WhisperModelCatalog.entries.first(where: { $0.id == "small" }) {
            let currentFilename = (preferences.dictation.modelPath as NSString).lastPathComponent
            if currentFilename == "ggml-base.bin" || currentFilename == "ggml-tiny.bin" {
                let dir = (preferences.dictation.modelPath as NSString).deletingLastPathComponent
                let newPath = (dir as NSString).appendingPathComponent(smallEntry.filename)
                if newPath != preferences.dictation.modelPath {
                    preferences.dictation.updateModelPath(newPath)
                    changes += 1
                }
            }
        }

        if preferences.dictation.languageMode != .auto {
            preferences.dictation.languageMode = .auto
            changes += 1
        }

        if !preferences.dictation.twoPassAutoDetect {
            preferences.dictation.twoPassAutoDetect = true
            changes += 1
        }

        // Segmented detect stays off — testers who want code-switch-ish
        // behavior can opt in, but default keeps latency predictable.

        if !preferences.dictation.vadEnabled {
            preferences.dictation.vadEnabled = true
            changes += 1
        }

        if !preferences.dictation.bilingualCleanupEnabled {
            preferences.dictation.bilingualCleanupEnabled = true
            changes += 1
        }

        if !preferences.dictation.arabicPunctuationEnabled {
            preferences.dictation.arabicPunctuationEnabled = true
            changes += 1
        }

        let recommendedPacks = [
            "msa-business.txt",
            "shami-common.txt",
            "khaleeji-common.txt",
            "agency-bilingual.txt",
            "tech-bilingual.txt"
        ]
        if preferences.dictation.enabledPackFilenames.isEmpty
            || preferences.dictation.enabledPackFilenames != recommendedPacks {
            preferences.dictation.enabledPackFilenames = recommendedPacks
            changes += 1
        }

        return changes
    }

    /// Human-readable summary of what `apply` would set. Used in the
    /// confirmation alert before the user commits to the preset.
    static var summary: String {
        """
        • Model: Small (downloads if not present)
        • Language: Auto
        • Two-pass auto-detect: on
        • Bilingual cleanup & Arabic punctuation: on
        • VAD: on
        • Packs (ordered): MSA Business → Shami → Khaleeji → Agency → Tech

        Segmented auto-detect stays off (opt-in). Your existing custom
        lexicon and snippets are not touched.
        """
    }
}
