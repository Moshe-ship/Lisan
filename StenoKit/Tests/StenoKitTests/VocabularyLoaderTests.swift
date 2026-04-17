import Foundation
import Testing
@testable import StenoKit

struct VocabularyLoaderTests {

    @Test("Returns nil when URL is nil")
    func nilURL() {
        #expect(WhisperCLITranscriptionEngine.loadVocabulary(at: nil) == nil)
    }

    @Test("Returns nil when path does not exist")
    func missingPath() {
        let url = URL(fileURLWithPath: "/tmp/definitely-does-not-exist-\(UUID().uuidString)")
        #expect(WhisperCLITranscriptionEngine.loadVocabulary(at: url) == nil)
    }

    @Test("Loads phrases from a single file")
    func singleFile() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let file = tmp.appendingPathComponent("vocab.txt")
        try "Alpha\nBeta\nGamma".write(to: file, atomically: true, encoding: .utf8)

        let result = WhisperCLITranscriptionEngine.loadVocabulary(at: file)
        #expect(result == "Alpha Beta Gamma")
    }

    @Test("Ignores comments and blank lines")
    func ignoresCommentsAndBlanks() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let file = tmp.appendingPathComponent("vocab.txt")
        try "# comment line\n\nAlpha\n   \nBeta\n# another comment\n".write(
            to: file, atomically: true, encoding: .utf8
        )

        let result = WhisperCLITranscriptionEngine.loadVocabulary(at: file)
        #expect(result == "Alpha Beta")
    }

    @Test("Dedupes repeated phrases across lines")
    func dedupes() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let file = tmp.appendingPathComponent("vocab.txt")
        try "Alpha\nBeta\nAlpha\nGamma\nBeta".write(to: file, atomically: true, encoding: .utf8)

        let result = WhisperCLITranscriptionEngine.loadVocabulary(at: file)
        #expect(result == "Alpha Beta Gamma")
    }

    @Test("Directory: reads all .txt files alphabetically")
    func directoryAlphabetical() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        // Files intentionally created out of order — loader should sort by name.
        try "Zeta".write(to: tmp.appendingPathComponent("z-pack.txt"), atomically: true, encoding: .utf8)
        try "Alpha".write(to: tmp.appendingPathComponent("a-pack.txt"), atomically: true, encoding: .utf8)
        try "Mid".write(to: tmp.appendingPathComponent("m-pack.txt"), atomically: true, encoding: .utf8)

        let result = WhisperCLITranscriptionEngine.loadVocabulary(at: tmp)
        #expect(result == "Alpha Mid Zeta")
    }

    @Test("Directory: ignores non-.txt files")
    func directoryIgnoresNonTxt() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        try "Alpha".write(to: tmp.appendingPathComponent("keep.txt"), atomically: true, encoding: .utf8)
        try "Garbage".write(to: tmp.appendingPathComponent("skip.md"), atomically: true, encoding: .utf8)
        try "Other".write(to: tmp.appendingPathComponent("skip.json"), atomically: true, encoding: .utf8)

        let result = WhisperCLITranscriptionEngine.loadVocabulary(at: tmp)
        #expect(result == "Alpha")
    }

    @Test("Directory: dedupes across files")
    func directoryDedupesAcrossFiles() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        try "Alpha\nShared".write(to: tmp.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try "Beta\nShared".write(to: tmp.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)

        let result = WhisperCLITranscriptionEngine.loadVocabulary(at: tmp)
        // "Shared" appears in both files but only once in the output.
        #expect(result == "Alpha Shared Beta")
    }

    @Test("Empty directory returns nil")
    func emptyDirectory() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        #expect(WhisperCLITranscriptionEngine.loadVocabulary(at: tmp) == nil)
    }

    @Test("Arabic phrases survive UTF-8 round trip")
    func arabicContent() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let file = tmp.appendingPathComponent("ar.txt")
        try "الرياض\nجدة\nمكة المكرمة".write(to: file, atomically: true, encoding: .utf8)

        let result = WhisperCLITranscriptionEngine.loadVocabulary(at: file)
        #expect(result == "الرياض جدة مكة المكرمة")
    }

    // MARK: - Helper

    private func makeTempDir() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("lisan-vocab-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
