import Foundation

// MARK: - Models

/// Language detected for a transcript chunk.
public enum DetectedLanguage: String, Sendable, Codable, Equatable {
    case arabic
    case english
    /// Significant mixing of Arabic and Latin within the same chunk.
    case mixed
    /// Neither — digits, symbols, or too short to classify.
    case other
}

/// A single language-tagged chunk of a transcript. Chunks preserve the
/// original whitespace and punctuation between them — joining `text`
/// values in order reconstructs the original input exactly.
public struct LanguageChunk: Sendable, Equatable {
    public let text: String
    public let language: DetectedLanguage

    public init(text: String, language: DetectedLanguage) {
        self.text = text
        self.language = language
    }
}

// MARK: - Splitter

/// Splits a raw transcript into language-tagged sentence chunks so that
/// each chunk can be routed to the cleanup pipeline appropriate to its
/// language.
///
/// Motivating bug: when Whisper produces mixed Arabic + English output
/// (either because the user code-switched or because auto-detect picked
/// one language but the speaker used both), applying English-only
/// cleanup rules to the whole string corrupts the Arabic parts (and
/// vice versa). This splitter lets the cleanup engine do the right
/// thing per-chunk.
///
/// Algorithm:
/// 1. Split on sentence terminators — ASCII `.`, `!`, `?` plus Arabic
///    full stop (`۔` U+06D4), Arabic question mark (`؟` U+061F), and
///    newlines. Keep the terminator with the preceding sentence.
/// 2. For each sentence, count Arabic scalars vs Latin-letter scalars.
/// 3. Classify:
///    - > 66% Arabic → `.arabic`
///    - > 66% Latin → `.english`
///    - Both present in meaningful amounts → `.mixed`
///    - Neither present → `.other` (pure digits, symbols, whitespace)
///
/// Pure function, `Sendable`, no state.
public struct BilingualSentenceSplitter: Sendable {

    /// Minimum share of total letter scalars required to "win" a classification.
    /// At 0.66, a sentence is Arabic if at least 2/3 of its letters are Arabic.
    public let majorityThreshold: Double

    public init(majorityThreshold: Double = 0.66) {
        precondition(majorityThreshold > 0.5 && majorityThreshold < 1.0,
                     "majorityThreshold must be in (0.5, 1.0)")
        self.majorityThreshold = majorityThreshold
    }

    public func split(_ text: String) -> [LanguageChunk] {
        guard !text.isEmpty else { return [] }

        var chunks: [LanguageChunk] = []
        var current = ""

        let scalars = Array(text.unicodeScalars)
        for (i, scalar) in scalars.enumerated() {
            current.unicodeScalars.append(scalar)
            let next = i + 1 < scalars.count ? scalars[i + 1] : nil
            if Self.isSentenceTerminator(scalar, nextScalar: next) {
                if !current.isEmpty {
                    chunks.append(classify(current))
                    current = ""
                }
            }
        }

        if !current.isEmpty {
            chunks.append(classify(current))
        }

        return chunks
    }

    /// Convenience: join classified chunks that share a language back into
    /// runs. Useful for callers that want a stable (text, language) boundary
    /// without trailing whitespace fragments.
    public func splitMerged(_ text: String) -> [LanguageChunk] {
        let chunks = split(text)
        guard !chunks.isEmpty else { return [] }

        var merged: [LanguageChunk] = []
        merged.reserveCapacity(chunks.count)

        for chunk in chunks {
            if let last = merged.last, last.language == chunk.language {
                merged[merged.count - 1] = LanguageChunk(
                    text: last.text + chunk.text,
                    language: last.language
                )
            } else {
                merged.append(chunk)
            }
        }
        return merged
    }

    // MARK: - Classification

    private func classify(_ sentence: String) -> LanguageChunk {
        // Strip URL / email / hashtag / mention runs before counting letters
        // so an Arabic sentence with one embedded https://... doesn't flip
        // to .mixed just because its Latin letter count exploded.
        let stripped = Self.stripNonLinguisticRuns(sentence)

        var arabicLetters = 0
        var latinLetters = 0

        for scalar in stripped.unicodeScalars {
            if Self.isArabicLetter(scalar) { arabicLetters += 1 }
            else if Self.isLatinLetter(scalar) { latinLetters += 1 }
        }

        let total = arabicLetters + latinLetters
        guard total > 0 else {
            return LanguageChunk(text: sentence, language: .other)
        }

        let arabicShare = Double(arabicLetters) / Double(total)
        let latinShare = Double(latinLetters) / Double(total)

        if arabicShare >= majorityThreshold {
            return LanguageChunk(text: sentence, language: .arabic)
        }
        if latinShare >= majorityThreshold {
            return LanguageChunk(text: sentence, language: .english)
        }
        return LanguageChunk(text: sentence, language: .mixed)
    }

    /// Remove character runs that aren't natural-language content:
    /// URLs (`https?://...`), email addresses, hashtags (`#foo`), and
    /// at-mentions (`@user`). Language classification should be based
    /// on actual words, not technical tokens that happen to use Latin
    /// letters. The returned string is only used for counting — the
    /// original chunk text is preserved for joining back together.
    private static func stripNonLinguisticRuns(_ text: String) -> String {
        // URLs: http(s)://... up to whitespace
        let urlPattern = #"https?://\S+"#
        // Emails: user@host.tld
        let emailPattern = #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#
        // Hashtags and mentions at the start of a token
        let hashMentionPattern = #"(?:^|\s)[#@][A-Za-z0-9_]+"#

        var working = text
        for pattern in [urlPattern, emailPattern, hashMentionPattern] {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(working.startIndex..<working.endIndex, in: working)
                working = regex.stringByReplacingMatches(in: working, range: range, withTemplate: " ")
            }
        }
        return working
    }

    // MARK: - Unicode ranges

    /// Sentence terminators that end a chunk. `.` is context-sensitive —
    /// it only ends a sentence when followed by whitespace or end-of-string
    /// so URLs, emails, decimals, and abbreviations stay in one chunk.
    /// Other terminators (`!`, `?`, Arabic `؟`, Urdu `۔`, newline) always end.
    private static func isSentenceTerminator(_ scalar: Unicode.Scalar, nextScalar: Unicode.Scalar?) -> Bool {
        switch scalar {
        case "!", "?",
             "\u{06D4}", // ۔ Arabic full stop (Urdu/Persian)
             "\u{061F}", // ؟ Arabic question mark
             "\n":
            return true
        case ".":
            // Only a terminator if followed by whitespace or string end.
            // Keeps URLs (lisan.app), emails (foo@bar.com), decimals (2.5),
            // and abbreviations (Mr. Smith — accepts the false merge) intact.
            guard let next = nextScalar else { return true }
            return CharacterSet.whitespacesAndNewlines.contains(next)
        default:
            return false
        }
    }

    /// Arabic script letter ranges. Excludes Arabic-Indic digits (0x0660-0x0669),
    /// combining marks (0x064B-0x065F, 0x0670), and punctuation. Covers base
    /// Arabic, Arabic Supplement, and Arabic Extended-A letter blocks.
    private static func isArabicLetter(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x0621...0x063A,  // base Arabic letters (hamza → ghayn)
             0x0641...0x064A,  // fa → ya
             0x066E...0x066F,  // Farsi variants
             0x0671...0x06D3,  // letters in extended blocks
             0x06D5,           // ae
             0x06FA...0x06FC,  // ligatures
             0x06FF,           // heh with inverted v
             0x0750...0x077F,  // Arabic Supplement
             0x08A0...0x08B4,  // Arabic Extended-A
             0x08B6...0x08BD,  // more Arabic Extended-A
             0xFB50...0xFDFF,  // Arabic Presentation Forms-A
             0xFE70...0xFEFC:  // Arabic Presentation Forms-B
            return true
        default:
            return false
        }
    }

    /// A-Z, a-z.
    private static func isLatinLetter(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar {
        case "A"..."Z", "a"..."z":
            return true
        default:
            return false
        }
    }
}
