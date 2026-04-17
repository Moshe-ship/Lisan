import Foundation

// MARK: - Options

/// User-configurable Arabic transformations for dictation output.
///
/// Unlike search normalization (which is intentionally aggressive — collapsing
/// many valid Arabic variants into a single canonical form so users find what
/// they're looking for), dictation normalization is about producing clean,
/// grammatically-correct written Arabic that matches the speaker's intent.
/// Some transforms (like ة → ه) are useful for search but WRONG in written
/// prose. Everything here is opt-in.
///
/// Defaults are the minimal, always-correct transforms:
/// - strip tashkeel: harakat are optional marks, speakers almost never dictate them
/// - strip tatweel: kashida is typographic decoration
/// - unify hamza-on-alif: common OCR/ASR artifact, rarely intentional
///
/// Everything else is off by default because it can change meaning.
public struct ArabicNormalizationOptions: Sendable, Codable, Equatable {
    /// Strip Arabic diacritics (ً ٌ ٍ َ ُ ِ ّ ْ ـً etc). On by default — Whisper rarely emits these and when it does they're usually noise.
    public var stripHarakat: Bool
    /// Strip tatweel (kashida, U+0640) — purely decorative.
    public var stripTatweel: Bool
    /// Unify alef variants: أ إ آ ٱ → ا. Useful when Whisper hallucinates the wrong hamza-on-alef.
    public var unifyAlef: Bool
    /// Unify ya variants: ى ئ → ي. Common in Egyptian/Gulf text but changes grammatical meaning in MSA.
    public var unifyYa: Bool
    /// Fold teh marbuta ة → ه. Useful for some dialects; OFF by default (changes meaning in MSA).
    public var foldTaMarbuta: Bool
    /// Fold waw with hamza ؤ → و. OFF by default (changes spelling).
    public var foldWawHamza: Bool
    /// Convert Arabic-Indic digits (٠-٩) and Persian digits (۰-۹) to ASCII 0-9.
    public var digitsToAscii: Bool
    /// Convert ASCII digits to Arabic-Indic digits (٠-٩). Mutually exclusive with digitsToAscii.
    public var digitsToArabic: Bool

    public static let `default` = ArabicNormalizationOptions(
        stripHarakat: true,
        stripTatweel: true,
        unifyAlef: true,
        unifyYa: false,
        foldTaMarbuta: false,
        foldWawHamza: false,
        digitsToAscii: false,
        digitsToArabic: false
    )

    public static let off = ArabicNormalizationOptions(
        stripHarakat: false,
        stripTatweel: false,
        unifyAlef: false,
        unifyYa: false,
        foldTaMarbuta: false,
        foldWawHamza: false,
        digitsToAscii: false,
        digitsToArabic: false
    )

    public init(
        stripHarakat: Bool,
        stripTatweel: Bool,
        unifyAlef: Bool,
        unifyYa: Bool,
        foldTaMarbuta: Bool,
        foldWawHamza: Bool,
        digitsToAscii: Bool,
        digitsToArabic: Bool
    ) {
        self.stripHarakat = stripHarakat
        self.stripTatweel = stripTatweel
        self.unifyAlef = unifyAlef
        self.unifyYa = unifyYa
        self.foldTaMarbuta = foldTaMarbuta
        self.foldWawHamza = foldWawHamza
        self.digitsToAscii = digitsToAscii
        self.digitsToArabic = digitsToArabic
    }
}

// MARK: - Normalizer

/// Applies user-selected Arabic transformations to dictation output.
///
/// Adapted from Aamil's `ArabicSearchNormalizer` (same Unicode tables, documented
/// provenance) but re-scoped for dictation rather than search. Search wants
/// aggressive folding; dictation wants optional, correctness-preserving transforms.
///
/// Pure function, unit-testable, no state. Operates on `Unicode.Scalar` to
/// preserve bidi marks and zero-width joiners that matter for RTL rendering.
public struct ArabicNormalizer: Sendable {

    public let options: ArabicNormalizationOptions

    public init(options: ArabicNormalizationOptions = .default) {
        self.options = options
    }

    /// Apply the configured transforms to `text` and return the result.
    public func normalize(_ text: String) -> String {
        guard !text.isEmpty else { return text }

        var result = ""
        result.reserveCapacity(text.unicodeScalars.count)

        for scalar in text.unicodeScalars {
            if options.stripHarakat, Self.isHarakat(scalar) { continue }
            if options.stripTatweel, scalar == Self.tatweel { continue }

            if let replacement = Self.mapScalar(scalar, options: options) {
                result.unicodeScalars.append(replacement)
                continue
            }

            result.unicodeScalars.append(scalar)
        }
        return result
    }

    // MARK: - Private tables

    /// Harakat (tashkeel) — diacritics that decorate base letters but don't
    /// carry meaning in standard modern Arabic prose. Range covers:
    /// - U+064B (tanwin fatḥ) through U+065F (combining hamza below)
    /// - U+0670 (superscript alef)
    ///
    /// Intentionally excludes U+0660-U+0669 (Arabic-Indic digits), which
    /// live right after this range and must NOT be stripped.
    private static func isHarakat(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x064B...0x065F, 0x0670:
            return true
        default:
            return false
        }
    }

    /// U+0640 — Arabic tatweel (kashida). Purely typographic decoration.
    private static let tatweel = Unicode.Scalar(0x0640)!

    /// Look up the folded form of `scalar` given the current options. Returns
    /// nil if the scalar is unchanged.
    private static func mapScalar(_ scalar: Unicode.Scalar, options: ArabicNormalizationOptions) -> Unicode.Scalar? {
        let v = scalar.value

        if options.unifyAlef {
            switch v {
            case 0x0622, 0x0623, 0x0625, 0x0671:
                return Unicode.Scalar(0x0627)! // ا
            default:
                break
            }
        }

        if options.unifyYa {
            switch v {
            case 0x0649, 0x0626:
                return Unicode.Scalar(0x064A)! // ي
            default:
                break
            }
        }

        if options.foldTaMarbuta, v == 0x0629 {
            return Unicode.Scalar(0x0647)! // ه
        }

        if options.foldWawHamza, v == 0x0624 {
            return Unicode.Scalar(0x0648)! // و
        }

        if options.digitsToAscii {
            if (0x0660...0x0669).contains(v) {
                return Unicode.Scalar(0x0030 + (v - 0x0660))!
            }
            if (0x06F0...0x06F9).contains(v) {
                return Unicode.Scalar(0x0030 + (v - 0x06F0))!
            }
        }

        if options.digitsToArabic {
            if (0x0030...0x0039).contains(v) {
                return Unicode.Scalar(0x0660 + (v - 0x0030))!
            }
        }

        return nil
    }
}
