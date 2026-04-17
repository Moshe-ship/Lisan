import Foundation

/// Converts ASCII punctuation to its Arabic equivalent within Arabic-majority
/// chunks of a transcript.
///
/// Whisper emits ASCII `,` `;` `?` even when it transcribes Arabic speech.
/// Native Arabic prose uses distinct glyphs:
///
/// | ASCII | Arabic | Name                       |
/// |-------|--------|----------------------------|
/// | `,`   | `،`    | U+060C Arabic comma        |
/// | `;`   | `؛`    | U+061B Arabic semicolon    |
/// | `?`   | `؟`    | U+061F Arabic question mark|
///
/// Full stop (`.`), exclamation (`!`), colon (`:`), and dash (`-`) are
/// identical in both scripts, so they pass through.
///
/// The punctuator runs per-chunk: callers pass already-classified
/// `LanguageChunk` values from `BilingualSentenceSplitter` and this service
/// transforms only the `.arabic` chunks. English chunks are untouched so
/// existing English commas/semicolons inside a bilingual paragraph survive.
///
/// Smart quotes are out of scope — Arabic quoting conventions vary heavily
/// by dialect and publisher. Ship when we have a user preference for it.
///
/// Pure function, `Sendable`, no state.
public struct ArabicPunctuator: Sendable {

    /// If true, convert within `.mixed` chunks too. Off by default — mixed
    /// chunks often contain English clauses whose punctuation shouldn't flip.
    public let convertMixedChunks: Bool

    public init(convertMixedChunks: Bool = false) {
        self.convertMixedChunks = convertMixedChunks
    }

    /// Convert punctuation in the text assuming it is already Arabic-majority.
    /// Use `punctuateChunks(_:)` for pipeline integration.
    public func punctuate(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        var result = ""
        result.reserveCapacity(text.unicodeScalars.count)
        for scalar in text.unicodeScalars {
            if let replacement = Self.map[scalar] {
                result.unicodeScalars.append(replacement)
            } else {
                result.unicodeScalars.append(scalar)
            }
        }
        return result
    }

    /// Apply Arabic punctuation to `.arabic` chunks (and `.mixed` chunks when
    /// configured). Other chunks pass through untouched.
    public func punctuateChunks(_ chunks: [LanguageChunk]) -> [LanguageChunk] {
        chunks.map { chunk in
            switch chunk.language {
            case .arabic:
                return LanguageChunk(text: punctuate(chunk.text), language: .arabic)
            case .mixed where convertMixedChunks:
                return LanguageChunk(text: punctuate(chunk.text), language: .mixed)
            default:
                return chunk
            }
        }
    }

    /// Convenience: join the chunks back into a string with Arabic punctuation applied.
    public func punctuate(chunks: [LanguageChunk]) -> String {
        punctuateChunks(chunks).map(\.text).joined()
    }

    // MARK: - Table

    private static let map: [Unicode.Scalar: Unicode.Scalar] = [
        Unicode.Scalar(0x002C)!: Unicode.Scalar(0x060C)!, // , → ،
        Unicode.Scalar(0x003B)!: Unicode.Scalar(0x061B)!, // ; → ؛
        Unicode.Scalar(0x003F)!: Unicode.Scalar(0x061F)!, // ? → ؟
    ]
}
