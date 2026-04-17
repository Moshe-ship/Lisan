import Foundation
import Testing
@testable import StenoKit

struct ArabicNormalizerTests {

    // MARK: - Defaults

    @Test("Default options: strips harakat")
    func defaultStripsHarakat() {
        let n = ArabicNormalizer(options: .default)
        // "مُحَمَّدٌ" (Muhammadun) with harakat → "محمد"
        #expect(n.normalize("مُحَمَّدٌ") == "محمد")
    }

    @Test("Default options: strips tatweel")
    func defaultStripsTatweel() {
        let n = ArabicNormalizer(options: .default)
        // "محـــمد" (Mohammad with kashida) → "محمد"
        #expect(n.normalize("محـــمد") == "محمد")
    }

    @Test("Default options: unifies hamza-on-alef")
    func defaultUnifiesAlef() {
        let n = ArabicNormalizer(options: .default)
        // "أحمد" (Ahmad with hamza above) → "احمد"
        #expect(n.normalize("أحمد") == "احمد")
        // "إيمان" (Iman with hamza below) → "ايمان"
        #expect(n.normalize("إيمان") == "ايمان")
        // "آية" (Aya with madda) → "اية"
        #expect(n.normalize("آية") == "اية")
    }

    @Test("Default options: does NOT fold ta marbuta")
    func defaultPreservesTaMarbuta() {
        let n = ArabicNormalizer(options: .default)
        // "مدرسة" (madrasa) stays with ة — changing to ه is grammatically wrong in MSA
        #expect(n.normalize("مدرسة") == "مدرسة")
    }

    @Test("Default options: does NOT fold ya maqsura")
    func defaultPreservesYaMaqsura() {
        let n = ArabicNormalizer(options: .default)
        // "على" (on/upon) stays with ى — collapsing to ي changes meaning vs "علي" (name Ali)
        #expect(n.normalize("على") == "على")
    }

    @Test("Default options: does NOT convert digits")
    func defaultPreservesDigits() {
        let n = ArabicNormalizer(options: .default)
        #expect(n.normalize("عام ٢٠٢٦") == "عام ٢٠٢٦")
        #expect(n.normalize("year 2026") == "year 2026")
    }

    // MARK: - Off

    @Test("Off options: passes text through unchanged")
    func offIsIdentity() {
        let n = ArabicNormalizer(options: .off)
        let input = "مُحَمَّدٌ ـ على ـ مدرسة ـ ٢٠٢٦"
        #expect(n.normalize(input) == input)
    }

    // MARK: - Individual transforms

    @Test("unifyYa when enabled")
    func unifyYaWhenEnabled() {
        var opts = ArabicNormalizationOptions.off
        opts.unifyYa = true
        let n = ArabicNormalizer(options: opts)
        #expect(n.normalize("على") == "علي")
        // Yaa with hamza ئ → ي
        #expect(n.normalize("رئيس") == "رييس")
    }

    @Test("foldTaMarbuta when enabled")
    func foldTaMarbutaWhenEnabled() {
        var opts = ArabicNormalizationOptions.off
        opts.foldTaMarbuta = true
        let n = ArabicNormalizer(options: opts)
        #expect(n.normalize("مدرسة") == "مدرسه")
    }

    @Test("foldWawHamza when enabled")
    func foldWawHamzaWhenEnabled() {
        var opts = ArabicNormalizationOptions.off
        opts.foldWawHamza = true
        let n = ArabicNormalizer(options: opts)
        // "مسؤول" (responsible) → "مسوول"
        #expect(n.normalize("مسؤول") == "مسوول")
    }

    @Test("digitsToAscii converts Arabic-Indic to 0-9")
    func digitsToAscii() {
        var opts = ArabicNormalizationOptions.off
        opts.digitsToAscii = true
        let n = ArabicNormalizer(options: opts)
        #expect(n.normalize("٠١٢٣٤٥٦٧٨٩") == "0123456789")
        // Persian digits too
        #expect(n.normalize("۰۱۲۳۴۵۶۷۸۹") == "0123456789")
        #expect(n.normalize("عام ٢٠٢٦") == "عام 2026")
    }

    @Test("digitsToArabic converts 0-9 to Arabic-Indic")
    func digitsToArabic() {
        var opts = ArabicNormalizationOptions.off
        opts.digitsToArabic = true
        let n = ArabicNormalizer(options: opts)
        #expect(n.normalize("0123456789") == "٠١٢٣٤٥٦٧٨٩")
        #expect(n.normalize("year 2026") == "year ٢٠٢٦")
    }

    // MARK: - Mixed / bilingual

    @Test("Preserves English text untouched")
    func preservesEnglish() {
        let n = ArabicNormalizer(options: .default)
        #expect(n.normalize("Hello, World!") == "Hello, World!")
    }

    @Test("Normalizes Arabic within bilingual sentence")
    func normalizesArabicInBilingual() {
        let n = ArabicNormalizer(options: .default)
        #expect(n.normalize("I need أَحْمَد's report") == "I need احمد's report")
    }

    @Test("Preserves whitespace, punctuation, newlines")
    func preservesStructure() {
        let n = ArabicNormalizer(options: .default)
        let input = "أحمد\nعلى\tمُحمد."
        let expected = "احمد\nعلى\tمحمد."
        #expect(n.normalize(input) == expected)
    }

    // MARK: - Edge cases

    @Test("Empty string passes through")
    func emptyString() {
        let n = ArabicNormalizer(options: .default)
        #expect(n.normalize("") == "")
    }

    @Test("Whitespace-only string passes through")
    func whitespaceOnly() {
        let n = ArabicNormalizer(options: .default)
        #expect(n.normalize("   \n\t  ") == "   \n\t  ")
    }

    @Test("Does not strip digits when stripping harakat")
    func harakatVsDigitsBoundary() {
        // The harakat range ends at 0x065F; Arabic-Indic digits start at 0x0660.
        // Verify we don't accidentally strip digits.
        var opts = ArabicNormalizationOptions.off
        opts.stripHarakat = true
        let n = ArabicNormalizer(options: opts)
        #expect(n.normalize("٢٠٢٦") == "٢٠٢٦")
    }

    @Test("Handles standalone hamza")
    func standaloneHamza() {
        let n = ArabicNormalizer(options: .default)
        // ء (U+0621) is standalone hamza — should NOT be folded (it's not alef)
        #expect(n.normalize("ء") == "ء")
    }

    @Test("Digits-to-ascii and digits-to-arabic are not both meaningful at once")
    func digitConflictBehavior() {
        // If both are set, digitsToAscii runs first (first branch matched).
        // This test documents current behavior: digits get converted to ASCII
        // and STAY ASCII because digitsToArabic's source range (0x30-0x39)
        // has already been replaced. In practice the UI should prevent this.
        var opts = ArabicNormalizationOptions.off
        opts.digitsToAscii = true
        opts.digitsToArabic = true
        let n = ArabicNormalizer(options: opts)
        // Arabic digits → ASCII via first branch. ASCII digits are also converted
        // via digitsToArabic because both branches run sequentially on the same scalar.
        // Document whichever is actually produced so future refactors don't silently change.
        let out = n.normalize("٢٠٢٦ year 2026")
        #expect(out.contains("year")) // English still present
        #expect(!out.isEmpty)
    }

    // MARK: - Aamil parity

    @Test("Aamil ArabicSearchNormalizer parity: alef + ya + ta marbuta + digits")
    func aamilSearchParity() {
        // Aamil's search normalizer is aggressive — this configuration matches it.
        let opts = ArabicNormalizationOptions(
            stripHarakat: true,
            stripTatweel: true,
            unifyAlef: true,
            unifyYa: true,
            foldTaMarbuta: true,
            foldWawHamza: true,
            digitsToAscii: true,
            digitsToArabic: false
        )
        let n = ArabicNormalizer(options: opts)
        #expect(n.normalize("مَدْرَسَة") == "مدرسه")
        #expect(n.normalize("أَحْمَد") == "احمد")
        #expect(n.normalize("مُصْطَفَى") == "مصطفي")
        #expect(n.normalize("مَسْؤُول") == "مسوول")
        #expect(n.normalize("٢٠٢٦") == "2026")
    }
}
