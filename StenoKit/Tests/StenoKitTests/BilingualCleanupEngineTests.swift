import Foundation
import Testing
@testable import StenoKit

struct BilingualCleanupEngineTests {

    // A tiny fake base engine that uppercases its input and reports one
    // filler removed. Lets us verify routing without depending on the real
    // rule-based engine.
    struct StubBase: CleanupEngine {
        func cleanup(
            raw: RawTranscript,
            profile: StyleProfile,
            lexicon: PersonalLexicon
        ) async throws -> CleanTranscript {
            CleanTranscript(
                text: raw.text.uppercased(),
                edits: [],
                removedFillers: ["um"],
                uncertaintyFlags: []
            )
        }
    }

    private static let profile = StyleProfile(
        name: "test",
        tone: .natural,
        structureMode: .natural,
        fillerPolicy: .aggressive,
        commandPolicy: .passthrough
    )
    private static let lexicon = PersonalLexicon(entries: [])

    @Test("Pure English → delegates entirely to base (fast path)")
    func pureEnglishFastPath() async throws {
        let engine = BilingualCleanupEngine(base: StubBase())
        let raw = RawTranscript(text: "hello world.", segments: [], avgConfidence: nil, durationMS: 0)
        let out = try await engine.cleanup(raw: raw, profile: Self.profile, lexicon: Self.lexicon)
        #expect(out.text == "HELLO WORLD.")
        #expect(out.removedFillers == ["um"])
    }

    @Test("Pure Arabic → base never touches the text")
    func pureArabicSkipsBase() async throws {
        let engine = BilingualCleanupEngine(base: StubBase())
        let raw = RawTranscript(text: "مرحباً كيف حالك?", segments: [], avgConfidence: nil, durationMS: 0)
        let out = try await engine.cleanup(raw: raw, profile: Self.profile, lexicon: Self.lexicon)
        // Base would uppercase — it doesn't run. Arabic normalization + punctuation DO run.
        // Default options strip harakat, unify alef. Input is already plain; punctuator
        // converts the ASCII question mark to Arabic ؟.
        #expect(out.text.contains("مرحبا") || out.text.contains("مرحباً"))
        #expect(out.text.contains("؟"))
        #expect(!out.text.contains("?"))
        #expect(out.removedFillers.isEmpty)  // base never ran
    }

    @Test("Arabic then English: each half routed correctly")
    func bilingualRouting() async throws {
        let engine = BilingualCleanupEngine(base: StubBase())
        let raw = RawTranscript(
            text: "هذا لسان. this is lisan.",
            segments: [], avgConfidence: nil, durationMS: 0
        )
        let out = try await engine.cleanup(raw: raw, profile: Self.profile, lexicon: Self.lexicon)
        // Arabic half untouched-uppercase, English half uppercased by stub base.
        #expect(out.text.contains("THIS IS LISAN."))
        #expect(!out.text.contains("هذا لسان") == false)  // arabic preserved
        #expect(out.removedFillers == ["um"])  // base ran on english half
    }

    @Test("Arabic punctuation disabled → ASCII punctuation preserved")
    func arabicPunctuationDisabled() async throws {
        let engine = BilingualCleanupEngine(
            base: StubBase(),
            arabicPunctuationEnabled: false
        )
        let raw = RawTranscript(text: "مرحباً, كيف حالك?", segments: [], avgConfidence: nil, durationMS: 0)
        let out = try await engine.cleanup(raw: raw, profile: Self.profile, lexicon: Self.lexicon)
        // Arabic chunk still normalized, but commas and question marks stay ASCII.
        #expect(out.text.contains("?"))
        #expect(out.text.contains(","))
        #expect(!out.text.contains("؟"))
        #expect(!out.text.contains("،"))
    }

    @Test("Custom options → transforms respected in Arabic chunks")
    func customOptions() async throws {
        var opts = ArabicNormalizationOptions.default
        opts.unifyYa = true
        opts.digitsToAscii = true
        let engine = BilingualCleanupEngine(base: StubBase(), options: opts)
        let raw = RawTranscript(text: "على ٢٠٢٦", segments: [], avgConfidence: nil, durationMS: 0)
        let out = try await engine.cleanup(raw: raw, profile: Self.profile, lexicon: Self.lexicon)
        #expect(out.text.contains("علي"))   // ى → ي
        #expect(out.text.contains("2026"))  // digits folded
    }

    @Test("Empty input → empty output (no errors)")
    func emptyInput() async throws {
        let engine = BilingualCleanupEngine(base: StubBase())
        let raw = RawTranscript(text: "", segments: [], avgConfidence: nil, durationMS: 0)
        let out = try await engine.cleanup(raw: raw, profile: Self.profile, lexicon: Self.lexicon)
        // Empty input has no Arabic chunks, so the fast path delegates to the base.
        // The stub uppercases "" which is still "". No crash expected.
        #expect(out.text == "")
    }

    @Test("Filler removals from base are aggregated across English chunks only")
    func fillerAggregation() async throws {
        let engine = BilingualCleanupEngine(base: StubBase())
        let raw = RawTranscript(
            text: "First english. مرحباً. Second english.",
            segments: [], avgConfidence: nil, durationMS: 0
        )
        let out = try await engine.cleanup(raw: raw, profile: Self.profile, lexicon: Self.lexicon)
        // Base was called twice (two english chunks) → two "um" entries.
        #expect(out.removedFillers.count == 2)
        #expect(out.removedFillers.allSatisfy { $0 == "um" })
    }
}
