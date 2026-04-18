import Foundation
import Testing
@testable import StenoKit

struct BilingualSentenceSplitterTests {

    // MARK: - Pure language inputs

    @Test("Pure English sentence → .english")
    func pureEnglishSingle() {
        let s = BilingualSentenceSplitter()
        let chunks = s.split("Hello, this is Lisan.")
        #expect(chunks.count == 1)
        #expect(chunks[0].language == .english)
        #expect(chunks[0].text == "Hello, this is Lisan.")
    }

    @Test("Pure Arabic sentence → .arabic")
    func pureArabicSingle() {
        let s = BilingualSentenceSplitter()
        let chunks = s.split("مرحباً، هذا لسان.")
        #expect(chunks.count == 1)
        #expect(chunks[0].language == .arabic)
        #expect(chunks[0].text == "مرحباً، هذا لسان.")
    }

    @Test("Multiple English sentences → multiple .english chunks")
    func multipleEnglish() {
        let s = BilingualSentenceSplitter()
        let chunks = s.split("Hello. How are you? I am fine!")
        #expect(chunks.count == 3)
        #expect(chunks.allSatisfy { $0.language == .english })
    }

    @Test("Multiple Arabic sentences → multiple .arabic chunks")
    func multipleArabic() {
        let s = BilingualSentenceSplitter()
        let chunks = s.split("مرحباً. كيف حالك؟ أنا بخير!")
        #expect(chunks.count == 3)
        #expect(chunks.allSatisfy { $0.language == .arabic })
    }

    // MARK: - Bilingual

    @Test("Arabic sentence then English sentence → two tagged chunks")
    func arabicThenEnglish() {
        let s = BilingualSentenceSplitter()
        let chunks = s.split("هذا لسان. This is Lisan.")
        #expect(chunks.count == 2)
        #expect(chunks[0].language == .arabic)
        #expect(chunks[1].language == .english)
    }

    @Test("English sentence then Arabic sentence → two tagged chunks")
    func englishThenArabic() {
        let s = BilingualSentenceSplitter()
        let chunks = s.split("This is Lisan. هذا لسان.")
        #expect(chunks.count == 2)
        #expect(chunks[0].language == .english)
        #expect(chunks[1].language == .arabic)
    }

    @Test("Heavy intra-sentence mixing → .mixed")
    func heavyMixing() {
        let s = BilingualSentenceSplitter()
        // Balanced Arabic + Latin letters — should land as .mixed.
        // Counts: Arabic letters 7 (ا ك ت ب today), Latin letters 7 (n o w today) → 50/50.
        let chunks = s.split("اكتب now today للعميل.")
        #expect(chunks.count == 1)
        #expect(chunks[0].language == .mixed)
    }

    @Test("Mostly Arabic with one English brand name → .arabic")
    func arabicWithBrandName() {
        let s = BilingualSentenceSplitter()
        // Dominant Arabic — one brand name shouldn't flip classification
        let chunks = s.split("نحتاج تقرير حملة Google لهذا الأسبوع.")
        #expect(chunks.count == 1)
        #expect(chunks[0].language == .arabic)
    }

    @Test("Mostly English with one Arabic name → .english")
    func englishWithArabicName() {
        let s = BilingualSentenceSplitter()
        // Dominant English — one Arabic name shouldn't flip classification
        let chunks = s.split("The meeting with أحمد is tomorrow afternoon.")
        #expect(chunks.count == 1)
        #expect(chunks[0].language == .english)
    }

    // MARK: - Round-trip preservation

    @Test("Joining chunk texts reconstructs the input exactly")
    func roundTripPreserved() {
        let s = BilingualSentenceSplitter()
        let input = "مرحباً. Hello! كيف حالك؟ I am fine."
        let chunks = s.split(input)
        let joined = chunks.map(\.text).joined()
        #expect(joined == input)
    }

    @Test("Joining merged-chunk texts reconstructs the input exactly")
    func roundTripPreservedAfterMerge() {
        let s = BilingualSentenceSplitter()
        let input = "Hello. How are you? مرحباً. كيف حالك؟"
        let merged = s.splitMerged(input)
        let joined = merged.map(\.text).joined()
        #expect(joined == input)
    }

    @Test("splitMerged merges adjacent same-language chunks")
    func mergeCollapsesAdjacent() {
        let s = BilingualSentenceSplitter()
        // Two adjacent English sentences → should merge into one chunk
        let merged = s.splitMerged("Hello. How are you?")
        #expect(merged.count == 1)
        #expect(merged[0].language == .english)
        #expect(merged[0].text == "Hello. How are you?")
    }

    @Test("splitMerged preserves language boundaries")
    func mergePreservesBoundaries() {
        let s = BilingualSentenceSplitter()
        let merged = s.splitMerged("Hello. مرحباً. How are you?")
        #expect(merged.count == 3)
        #expect(merged[0].language == .english)
        #expect(merged[1].language == .arabic)
        #expect(merged[2].language == .english)
    }

    // MARK: - Punctuation

    @Test("Arabic question mark ends a sentence")
    func arabicQuestionMark() {
        let s = BilingualSentenceSplitter()
        let chunks = s.split("كيف حالك؟ أنا بخير")
        #expect(chunks.count == 2)
    }

    @Test("Newline ends a sentence")
    func newlineTerminates() {
        let s = BilingualSentenceSplitter()
        let chunks = s.split("First line\nSecond line")
        #expect(chunks.count == 2)
    }

    // MARK: - Edge cases

    @Test("Empty input → no chunks")
    func emptyInput() {
        let s = BilingualSentenceSplitter()
        #expect(s.split("").isEmpty)
    }

    @Test("Whitespace-only input → single .other chunk")
    func whitespaceOnly() {
        let s = BilingualSentenceSplitter()
        let chunks = s.split("   \t  ")
        #expect(chunks.count == 1)
        #expect(chunks[0].language == .other)
    }

    @Test("Digits-only input → .other")
    func digitsOnly() {
        let s = BilingualSentenceSplitter()
        let chunks = s.split("2026 ٢٠٢٦ 123.")
        #expect(chunks[0].language == .other)
    }

    @Test("Trailing fragment without terminator is captured")
    func trailingFragment() {
        let s = BilingualSentenceSplitter()
        let chunks = s.split("Hello. This has no period")
        #expect(chunks.count == 2)
        #expect(chunks[1].text == " This has no period")
    }

    @Test("Threshold of 0.66 classifies 2-Arabic-out-of-3 as Arabic")
    func thresholdBoundary() {
        let s = BilingualSentenceSplitter(majorityThreshold: 0.66)
        // 2 Arabic letters + 1 Latin letter = 66.6% Arabic
        let chunks = s.split("اب c")
        #expect(chunks[0].language == .arabic)
    }

    @Test("Custom lower threshold makes classification more permissive")
    func customThreshold() {
        let s = BilingualSentenceSplitter(majorityThreshold: 0.55)
        // Mostly English with some Arabic — custom threshold should still pick English
        let chunks = s.split("Lisan transcript with one word كلمة.")
        #expect(chunks[0].language == .english)
    }

    // MARK: - Non-linguistic runs

    @Test("Arabic sentence with embedded URL stays .arabic")
    func arabicWithURL() {
        let s = BilingualSentenceSplitter()
        // Without URL stripping, this would flip to .mixed because the URL
        // has many Latin letters. With stripping, only the Arabic word ratio matters.
        let chunks = s.split("زوروا https://lisan.app/docs لمعرفة المزيد عن لسان.")
        #expect(chunks.count == 1)
        #expect(chunks[0].language == .arabic)
        // Original text preserved — URL is only excluded from CLASSIFICATION.
        #expect(chunks[0].text.contains("https://lisan.app/docs"))
    }

    @Test("Arabic sentence with embedded email stays .arabic")
    func arabicWithEmail() {
        let s = BilingualSentenceSplitter()
        let chunks = s.split("راسلوني على mousa@example.com لأي استفسار.")
        #expect(chunks[0].language == .arabic)
    }

    @Test("Arabic sentence with hashtag stays .arabic")
    func arabicWithHashtag() {
        let s = BilingualSentenceSplitter()
        let chunks = s.split("منشور جديد حول #AISaudi شكراً للجميع.")
        #expect(chunks[0].language == .arabic)
    }

    @Test("Arabic sentence with @mention stays .arabic")
    func arabicWithMention() {
        let s = BilingualSentenceSplitter()
        let chunks = s.split("شكراً @NousResearch على الدعم المستمر للعرب.")
        #expect(chunks[0].language == .arabic)
    }

    @Test("English sentence with an Arabic-in-URL doesn't break classification")
    func englishWithArabicParam() {
        let s = BilingualSentenceSplitter()
        let chunks = s.split("See the page at https://example.com/?q=مرحبا for details.")
        #expect(chunks[0].language == .english)
    }

    @Test("URL-only content classifies as .other, not .english")
    func urlOnly() {
        let s = BilingualSentenceSplitter()
        let chunks = s.split("https://github.com/Moshe-ship/Lisan")
        #expect(chunks[0].language == .other)
    }
}
