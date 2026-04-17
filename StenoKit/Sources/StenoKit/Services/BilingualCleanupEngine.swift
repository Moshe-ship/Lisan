import Foundation

/// CleanupEngine that routes each sentence chunk through language-appropriate
/// cleanup: English rules for English chunks, Arabic normalization +
/// optional Arabic punctuation for Arabic chunks, pass-through for everything else.
///
/// This is the fix for the observed bug: when a transcript mixes Arabic and
/// English, applying English-only cleanup rules to the Arabic parts produces
/// corrupted output (filler-removal regexes matching Arabic words, English
/// capitalization applied to Arabic). Routing per-chunk keeps each language
/// in its own pipeline.
///
/// ```
/// raw transcript
///   │
///   ▼
/// BilingualSentenceSplitter → [chunk, chunk, chunk]
///   │
///   ▼ per chunk
/// .english → base CleanupEngine
/// .arabic  → ArabicNormalizer → ArabicPunctuator (optional)
/// .mixed   → base CleanupEngine  (English rules; better than corrupting)
/// .other   → untouched
///   │
///   ▼
/// join in original order
/// ```
///
/// Fast path: when the transcript contains no Arabic chunks, the base engine
/// runs on the whole input — zero overhead for English-only users.
public struct BilingualCleanupEngine: CleanupEngine, Sendable {

    public let base: CleanupEngine
    public let options: ArabicNormalizationOptions
    public let arabicPunctuationEnabled: Bool

    private let splitter: BilingualSentenceSplitter
    private let normalizer: ArabicNormalizer
    private let punctuator: ArabicPunctuator

    public init(
        base: CleanupEngine,
        options: ArabicNormalizationOptions = .default,
        arabicPunctuationEnabled: Bool = true,
        splitterThreshold: Double = 0.66
    ) {
        self.base = base
        self.options = options
        self.arabicPunctuationEnabled = arabicPunctuationEnabled
        self.splitter = BilingualSentenceSplitter(majorityThreshold: splitterThreshold)
        self.normalizer = ArabicNormalizer(options: options)
        self.punctuator = ArabicPunctuator(convertMixedChunks: false)
    }

    public func cleanup(
        raw: RawTranscript,
        profile: StyleProfile,
        lexicon: PersonalLexicon
    ) async throws -> CleanTranscript {
        let chunks = splitter.split(raw.text)

        let hasArabic = chunks.contains { $0.language == .arabic }
        guard hasArabic else {
            return try await base.cleanup(raw: raw, profile: profile, lexicon: lexicon)
        }

        var output = ""
        output.reserveCapacity(raw.text.count)
        var cumulativeRemovedFillers: [String] = []

        for chunk in chunks {
            switch chunk.language {
            case .arabic:
                let normalized = normalizer.normalize(chunk.text)
                let punctuated = arabicPunctuationEnabled
                    ? punctuator.punctuate(normalized)
                    : normalized
                output += punctuated

            case .english, .mixed:
                let sub = RawTranscript(
                    text: chunk.text,
                    segments: [],
                    avgConfidence: raw.avgConfidence,
                    durationMS: raw.durationMS
                )
                let cleaned = try await base.cleanup(raw: sub, profile: profile, lexicon: lexicon)
                output += cleaned.text
                cumulativeRemovedFillers.append(contentsOf: cleaned.removedFillers)

            case .other:
                output += chunk.text
            }
        }

        return CleanTranscript(
            text: output,
            edits: [],
            removedFillers: cumulativeRemovedFillers,
            uncertaintyFlags: []
        )
    }
}
