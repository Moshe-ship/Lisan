import Foundation
import StenoKit

struct AppPreferences: Codable, Sendable, Equatable {
    struct General: Codable, Sendable, Equatable {
        var launchAtLoginEnabled: Bool
        var showDockIcon: Bool
        var showOnboarding: Bool
        /// When false, transcript history lives only in memory and is
        /// erased at app quit. Default true preserves the pre-privacy-
        /// audit behavior; privacy-conscious users can flip it off.
        var persistHistoryOnDisk: Bool
        /// Entries older than this are pruned from both memory and the
        /// on-disk JSON on every append. Default 30 days.
        var historyRetentionDays: Int

        init(
            launchAtLoginEnabled: Bool,
            showDockIcon: Bool,
            showOnboarding: Bool,
            persistHistoryOnDisk: Bool = true,
            historyRetentionDays: Int = 30
        ) {
            self.launchAtLoginEnabled = launchAtLoginEnabled
            self.showDockIcon = showDockIcon
            self.showOnboarding = showOnboarding
            self.persistHistoryOnDisk = persistHistoryOnDisk
            self.historyRetentionDays = historyRetentionDays
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            launchAtLoginEnabled = try container.decodeIfPresent(Bool.self, forKey: .launchAtLoginEnabled) ?? false
            showDockIcon = try container.decodeIfPresent(Bool.self, forKey: .showDockIcon) ?? true
            showOnboarding = try container.decodeIfPresent(Bool.self, forKey: .showOnboarding) ?? false
            persistHistoryOnDisk = try container.decodeIfPresent(Bool.self, forKey: .persistHistoryOnDisk) ?? true
            historyRetentionDays = try container.decodeIfPresent(Int.self, forKey: .historyRetentionDays) ?? 30
        }
    }

    struct Hotkeys: Codable, Sendable, Equatable {
        var optionPressToTalkEnabled: Bool
        var handsFreeGlobalKeyCode: UInt16?

        init(optionPressToTalkEnabled: Bool, handsFreeGlobalKeyCode: UInt16? = 79) {
            self.optionPressToTalkEnabled = optionPressToTalkEnabled
            self.handsFreeGlobalKeyCode = handsFreeGlobalKeyCode
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            optionPressToTalkEnabled = try container.decodeIfPresent(Bool.self, forKey: .optionPressToTalkEnabled) ?? true
            handsFreeGlobalKeyCode = try container.decodeIfPresent(UInt16.self, forKey: .handsFreeGlobalKeyCode) ?? 79
        }
    }

    struct Dictation: Codable, Sendable, Equatable {
        var whisperCLIPath: String
        var modelPath: String
        var threadCount: Int
        var vadEnabled: Bool
        var vadModelPath: String
        /// Primary dictation language: en, ar, or auto.
        var languageMode: LanguageMode
        /// Path to a plain-text vocabulary file (one phrase per line). Used to
        /// bias recognition toward custom terms, brand names, and transliterations.
        var vocabularyFilePath: String
        /// Turn Arabic-aware cleanup on or off. When on, the pipeline splits
        /// bilingual transcripts and runs Arabic normalization + punctuation
        /// on Arabic sentences while leaving English sentences to the base
        /// engine. Fast-paths to base when no Arabic is detected.
        var bilingualCleanupEnabled: Bool
        /// Per-transform toggles for Arabic normalization. See ArabicNormalizationOptions.
        var arabicOptions: ArabicNormalizationOptions
        /// Convert ASCII `,` `;` `?` to Arabic `،` `؛` `؟` inside Arabic chunks.
        var arabicPunctuationEnabled: Bool
        /// When true and languageMode is .auto, run a whisper `-dl`
        /// preflight to detect language before full transcription. More
        /// accurate for short Arabic clips; costs one extra model-load per
        /// dictation. Off by default.
        var twoPassAutoDetect: Bool
        /// Ordered list of vocabulary pack filenames to enable, highest
        /// priority first. Empty means "load every .txt in the
        /// vocabularyFilePath directory" (legacy all-packs behavior).
        /// Only consulted when vocabularyFilePath points at a directory.
        var enabledPackFilenames: [String]
        /// Split long recordings on silence and transcribe each segment
        /// independently (per-segment language detection). The closest
        /// honest thing to code-switch support whisper.cpp supports —
        /// phrase-level, not word-level. Off by default; opt-in because
        /// it multiplies latency by segment count.
        var segmentedAutoDetect: Bool

        init(
            whisperCLIPath: String,
            modelPath: String,
            threadCount: Int,
            vadEnabled: Bool = true,
            vadModelPath: String? = nil,
            languageMode: LanguageMode = .auto,
            vocabularyFilePath: String = "",
            bilingualCleanupEnabled: Bool = true,
            arabicOptions: ArabicNormalizationOptions = .default,
            arabicPunctuationEnabled: Bool = true,
            twoPassAutoDetect: Bool = false,
            enabledPackFilenames: [String] = [],
            segmentedAutoDetect: Bool = false
        ) {
            self.whisperCLIPath = whisperCLIPath
            self.modelPath = modelPath
            self.threadCount = threadCount
            self.vadEnabled = vadEnabled
            self.vadModelPath = vadModelPath ?? WhisperRuntimeConfiguration.defaultVADModelPath(relativeTo: modelPath)
            self.languageMode = languageMode
            self.vocabularyFilePath = vocabularyFilePath
            self.bilingualCleanupEnabled = bilingualCleanupEnabled
            self.arabicOptions = arabicOptions
            self.arabicPunctuationEnabled = arabicPunctuationEnabled
            self.twoPassAutoDetect = twoPassAutoDetect
            self.enabledPackFilenames = enabledPackFilenames
            self.segmentedAutoDetect = segmentedAutoDetect
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            whisperCLIPath = try container.decode(String.self, forKey: .whisperCLIPath)
            modelPath = try container.decode(String.self, forKey: .modelPath)
            threadCount = try container.decodeIfPresent(Int.self, forKey: .threadCount) ?? 6
            vadEnabled = try container.decodeIfPresent(Bool.self, forKey: .vadEnabled) ?? true
            let savedVAD = try container.decodeIfPresent(String.self, forKey: .vadModelPath)
            vadModelPath = savedVAD ?? WhisperRuntimeConfiguration.defaultVADModelPath(relativeTo: modelPath)
            languageMode = try container.decodeIfPresent(LanguageMode.self, forKey: .languageMode) ?? .auto
            vocabularyFilePath = try container.decodeIfPresent(String.self, forKey: .vocabularyFilePath) ?? ""
            bilingualCleanupEnabled = try container.decodeIfPresent(Bool.self, forKey: .bilingualCleanupEnabled) ?? true
            arabicOptions = try container.decodeIfPresent(ArabicNormalizationOptions.self, forKey: .arabicOptions) ?? .default
            arabicPunctuationEnabled = try container.decodeIfPresent(Bool.self, forKey: .arabicPunctuationEnabled) ?? true
            twoPassAutoDetect = try container.decodeIfPresent(Bool.self, forKey: .twoPassAutoDetect) ?? false
            enabledPackFilenames = try container.decodeIfPresent([String].self, forKey: .enabledPackFilenames) ?? []
            segmentedAutoDetect = try container.decodeIfPresent(Bool.self, forKey: .segmentedAutoDetect) ?? false
        }

        mutating func updateModelPath(_ newModelPath: String) {
            vadModelPath = WhisperRuntimeConfiguration.syncedVADModelPath(
                currentVADModelPath: vadModelPath,
                previousModelPath: modelPath,
                newModelPath: newModelPath
            )
            modelPath = newModelPath
        }
    }

    struct Insertion: Codable, Sendable, Equatable {
        var orderedMethods: [InsertionMethod]

        init(orderedMethods: [InsertionMethod]) {
            self.orderedMethods = orderedMethods
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            orderedMethods = try container.decodeIfPresent([InsertionMethod].self, forKey: .orderedMethods) ?? [.direct, .accessibility, .clipboardPaste]
        }
    }

    struct Media: Codable, Sendable, Equatable {
        var pauseDuringHandsFree: Bool
        var pauseDuringPressToTalk: Bool

        init(pauseDuringHandsFree: Bool = true, pauseDuringPressToTalk: Bool = true) {
            self.pauseDuringHandsFree = pauseDuringHandsFree
            self.pauseDuringPressToTalk = pauseDuringPressToTalk
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            pauseDuringHandsFree = try container.decodeIfPresent(Bool.self, forKey: .pauseDuringHandsFree) ?? true
            pauseDuringPressToTalk = try container.decodeIfPresent(Bool.self, forKey: .pauseDuringPressToTalk) ?? true
        }
    }

    var general: General
    var hotkeys: Hotkeys
    var dictation: Dictation
    var insertion: Insertion
    var media: Media

    var lexiconEntries: [LexiconEntry]
    var globalStyleProfile: StyleProfile
    var appStyleProfiles: [String: StyleProfile]
    var snippets: [Snippet]

    static var `default`: AppPreferences {
        let vendorRoot = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("vendor/whisper.cpp", isDirectory: true)
            .path

        return AppPreferences(
            general: .init(
                launchAtLoginEnabled: false,
                showDockIcon: true,
                showOnboarding: true
            ),
            hotkeys: .init(
                optionPressToTalkEnabled: true,
                handsFreeGlobalKeyCode: 79
            ),
            dictation: .init(
                whisperCLIPath: "\(vendorRoot)/build/bin/whisper-cli",
                modelPath: "\(vendorRoot)/models/ggml-base.bin",
                threadCount: 6,
                languageMode: .auto,
                vocabularyFilePath: ""
            ),
            insertion: .init(orderedMethods: [.direct, .accessibility, .clipboardPaste]),
            media: .init(pauseDuringHandsFree: true, pauseDuringPressToTalk: true),
            lexiconEntries: [
                LexiconEntry(term: "stenoh", preferred: "Steno", scope: .global),
                LexiconEntry(term: "steno kit", preferred: "StenoKit", scope: .global)
            ],
            globalStyleProfile: .init(
                name: "Default",
                tone: .natural,
                structureMode: .paragraph,
                fillerPolicy: .balanced,
                commandPolicy: .transform
            ),
            appStyleProfiles: [:],
            snippets: []
        )
    }

    mutating func normalize() {
        let supported: Set<InsertionMethod> = [.direct, .accessibility, .clipboardPaste]
        var seen: Set<InsertionMethod> = []
        var normalized: [InsertionMethod] = []

        for method in insertion.orderedMethods where supported.contains(method) && !seen.contains(method) {
            normalized.append(method)
            seen.insert(method)
        }

        if !seen.contains(.clipboardPaste) {
            normalized.append(.clipboardPaste)
        }

        insertion.orderedMethods = normalized
        dictation.threadCount = max(1, min(16, dictation.threadCount))
    }
}
