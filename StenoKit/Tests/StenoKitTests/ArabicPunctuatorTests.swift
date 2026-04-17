import Foundation
import Testing
@testable import StenoKit

struct ArabicPunctuatorTests {

    @Test("Converts ASCII comma to Arabic comma")
    func commaConversion() {
        let p = ArabicPunctuator()
        #expect(p.punctuate("مرحباً، كيف حالك") == "مرحباً، كيف حالك")
        #expect(p.punctuate("مرحباً, كيف حالك") == "مرحباً، كيف حالك")
    }

    @Test("Converts ASCII semicolon to Arabic semicolon")
    func semicolonConversion() {
        let p = ArabicPunctuator()
        #expect(p.punctuate("أولاً; ثانياً") == "أولاً؛ ثانياً")
    }

    @Test("Converts ASCII question mark to Arabic question mark")
    func questionMarkConversion() {
        let p = ArabicPunctuator()
        #expect(p.punctuate("كيف حالك?") == "كيف حالك؟")
    }

    @Test("Leaves full stop unchanged")
    func fullStopPassthrough() {
        let p = ArabicPunctuator()
        #expect(p.punctuate("مرحباً.") == "مرحباً.")
    }

    @Test("Leaves exclamation unchanged")
    func exclamationPassthrough() {
        let p = ArabicPunctuator()
        #expect(p.punctuate("رائع!") == "رائع!")
    }

    @Test("Leaves colon unchanged")
    func colonPassthrough() {
        let p = ArabicPunctuator()
        #expect(p.punctuate("السؤال: ما هذا") == "السؤال: ما هذا")
    }

    @Test("Empty string passes through")
    func emptyInput() {
        let p = ArabicPunctuator()
        #expect(p.punctuate("") == "")
    }

    @Test("No-op for pure English when called directly")
    func englishDirectCall() {
        // Calling punctuate() directly on English will still convert — that's
        // why the chunked API exists. This documents the low-level behavior.
        let p = ArabicPunctuator()
        #expect(p.punctuate("Hello, world?") == "Hello، world؟")
    }

    // MARK: - Chunked API (the pipeline-safe one)

    @Test("punctuateChunks only transforms .arabic chunks")
    func chunksOnlyArabic() {
        let p = ArabicPunctuator()
        let chunks: [LanguageChunk] = [
            LanguageChunk(text: "Hello, world?", language: .english),
            LanguageChunk(text: " مرحباً، كيف حالك?", language: .arabic),
        ]
        let out = p.punctuateChunks(chunks)
        #expect(out[0].text == "Hello, world?")
        #expect(out[1].text == " مرحباً، كيف حالك؟")
    }

    @Test("punctuateChunks leaves .mixed chunks unchanged by default")
    func chunksMixedDefault() {
        let p = ArabicPunctuator()
        let chunks: [LanguageChunk] = [
            LanguageChunk(text: "اكتب email للعميل, please?", language: .mixed),
        ]
        let out = p.punctuateChunks(chunks)
        #expect(out[0].text == "اكتب email للعميل, please?")
    }

    @Test("punctuateChunks converts .mixed when opted in")
    func chunksMixedOptIn() {
        let p = ArabicPunctuator(convertMixedChunks: true)
        let chunks: [LanguageChunk] = [
            LanguageChunk(text: "اكتب email, please?", language: .mixed),
        ]
        let out = p.punctuateChunks(chunks)
        #expect(out[0].text == "اكتب email، please؟")
    }

    @Test("punctuateChunks preserves .other and .english exactly")
    func chunksOtherUntouched() {
        let p = ArabicPunctuator()
        let chunks: [LanguageChunk] = [
            LanguageChunk(text: "2026, v1?", language: .other),
            LanguageChunk(text: "Hello?", language: .english),
        ]
        let out = p.punctuateChunks(chunks)
        #expect(out[0].text == "2026, v1?")
        #expect(out[1].text == "Hello?")
    }

    // MARK: - End-to-end with splitter

    @Test("End-to-end: splitter then punctuator on mixed input")
    func splitterThenPunctuator() {
        let s = BilingualSentenceSplitter()
        let p = ArabicPunctuator()
        let chunks = s.split("Hello, world? مرحباً, كيف حالك?")
        let out = p.punctuateChunks(chunks)
        let joined = out.map(\.text).joined()
        // English part: comma and ? stay ASCII. Arabic part: comma becomes ، and ? becomes ؟.
        #expect(joined.contains("Hello, world?"))
        #expect(joined.contains("مرحباً، كيف حالك؟"))
    }

    @Test("End-to-end: convenience punctuate(chunks:) returns joined string")
    func convenienceJoin() {
        let s = BilingualSentenceSplitter()
        let p = ArabicPunctuator()
        let input = "Hello, world? مرحباً, كيف حالك?"
        let chunks = s.split(input)
        let result = p.punctuate(chunks: chunks)
        #expect(result.contains("Hello, world?"))
        #expect(result.contains("مرحباً، كيف حالك؟"))
    }

    @Test("Round-trip: joining punctuated chunks preserves structure")
    func roundTripStructure() {
        let s = BilingualSentenceSplitter()
        let p = ArabicPunctuator()
        let chunks = s.split("First. مرحباً. Second?")
        let out = p.punctuateChunks(chunks)
        // Same number of chunks, same languages as input
        #expect(out.count == chunks.count)
        for (a, b) in zip(out, chunks) {
            #expect(a.language == b.language)
        }
    }
}
