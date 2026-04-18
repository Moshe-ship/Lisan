import Foundation
import Testing
@testable import StenoKit

@Test("Catalog exposes the four expected multilingual models in order")
func catalogOrder() {
    let ids = WhisperModelCatalog.entries.map { $0.id }
    #expect(ids == ["tiny", "base", "small", "medium"])
}

@Test("Catalog download URLs all point at huggingface ggerganov/whisper.cpp")
func catalogURLsWellFormed() {
    for entry in WhisperModelCatalog.entries {
        #expect(entry.downloadURL.host == "huggingface.co")
        #expect(entry.downloadURL.path.contains("ggerganov/whisper.cpp"))
        #expect(entry.downloadURL.path.hasSuffix(entry.filename))
    }
}

@Test("Catalog expected sizes are all > 50 MB (sanity floor)")
func catalogSizesReasonable() {
    for entry in WhisperModelCatalog.entries {
        #expect(entry.expectedSizeBytes > 50_000_000,
                "\(entry.displayName) size \(entry.expectedSizeBytes) looks too small")
    }
}

@Test("entry(forModelPath:) matches catalog entries by filename")
func resolveByPath() {
    let match = WhisperModelCatalog.entry(forModelPath: "/some/path/ggml-small.bin")
    #expect(match?.id == "small")

    let matchAbs = WhisperModelCatalog.entry(
        forModelPath: "/Users/x/vendor/whisper.cpp/models/ggml-medium.bin"
    )
    #expect(matchAbs?.id == "medium")
}

@Test("entry(forModelPath:) returns nil for custom or unrecognized filenames")
func resolveByPathMiss() {
    #expect(WhisperModelCatalog.entry(forModelPath: "/tmp/my-own-model.bin") == nil)
    #expect(WhisperModelCatalog.entry(forModelPath: "") == nil)
    #expect(WhisperModelCatalog.entry(forModelPath: "/models/ggml-large-v3.bin") == nil)
}

@Test("isInstalled returns false when file is missing")
func isInstalledMissing() throws {
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("catalog-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    let entry = WhisperModelCatalog.entries.first { $0.id == "small" }!
    #expect(WhisperModelCatalog.isInstalled(entry: entry, in: tmp) == false)
}

@Test("isInstalled returns true when a file ≥ 95% of expected size exists")
func isInstalledPresent() throws {
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("catalog-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    let entry = WhisperModelCatalog.entries.first { $0.id == "tiny" }!
    // Write a file at the expected filename with 98% of the expected size.
    let target = tmp.appendingPathComponent(entry.filename)
    let payloadSize = Int(Double(entry.expectedSizeBytes) * 0.98)
    let data = Data(count: payloadSize)
    try data.write(to: target)

    #expect(WhisperModelCatalog.isInstalled(entry: entry, in: tmp) == true)
}

@Test("isInstalled rejects partial downloads below 95% threshold")
func isInstalledPartial() throws {
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("catalog-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    let entry = WhisperModelCatalog.entries.first { $0.id == "tiny" }!
    let target = tmp.appendingPathComponent(entry.filename)
    // 50% of expected size = interrupted download. Should be rejected.
    let data = Data(count: Int(entry.expectedSizeBytes / 2))
    try data.write(to: target)

    #expect(WhisperModelCatalog.isInstalled(entry: entry, in: tmp) == false)
}
