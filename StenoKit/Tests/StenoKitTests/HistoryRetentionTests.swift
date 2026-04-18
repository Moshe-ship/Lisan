import Foundation
import Testing
@testable import StenoKit

/// Privacy-retention tests for HistoryStore: confirms the 30-day (or
/// configured) retention cap actually shrinks the on-disk file, that
/// the persistOnDisk toggle clears the file, and that writes land with
/// 0600 permissions.

@Test("Retention: entries older than retentionDays are pruned on append")
func historyPrunesOldEntriesOnAppend() async throws {
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("history-retention-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: tmp) }

    let store = HistoryStore(
        storageURL: tmp,
        clipboardService: StubClipboardService(),
        maxEntries: 500,
        persistOnDisk: true,
        retentionDays: 7
    )

    // 20-day-old entry should be pruned; 1-day-old should survive.
    let oldEntry = TranscriptEntry(
        id: UUID(),
        createdAt: Date().addingTimeInterval(-20 * 86_400),
        appBundleID: "com.example.old",
        rawText: "old raw",
        cleanText: "old clean",
        audioURL: nil,
        insertionStatus: .inserted
    )
    let recentEntry = TranscriptEntry(
        id: UUID(),
        createdAt: Date().addingTimeInterval(-1 * 86_400),
        appBundleID: "com.example.recent",
        rawText: "recent raw",
        cleanText: "recent clean",
        audioURL: nil,
        insertionStatus: .inserted
    )

    try await store.append(entry: oldEntry)
    try await store.append(entry: recentEntry)

    let result = await store.recent(limit: 100)
    #expect(result.count == 1, "Old entry should have been pruned")
    #expect(result.first?.appBundleID == "com.example.recent")
}

@Test("Retention: on-disk JSON only contains post-retention entries")
func historyOnDiskJSONReflectsRetention() async throws {
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("history-disk-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: tmp) }

    let store = HistoryStore(
        storageURL: tmp,
        clipboardService: StubClipboardService(),
        maxEntries: 500,
        persistOnDisk: true,
        retentionDays: 3
    )

    let old = TranscriptEntry(
        id: UUID(),
        createdAt: Date().addingTimeInterval(-10 * 86_400),
        appBundleID: "com.old",
        rawText: "old",
        cleanText: "old",
        audioURL: nil,
        insertionStatus: .inserted
    )
    let fresh = TranscriptEntry(
        id: UUID(),
        createdAt: Date(),
        appBundleID: "com.fresh",
        rawText: "fresh",
        cleanText: "fresh",
        audioURL: nil,
        insertionStatus: .inserted
    )
    try await store.append(entry: old)
    try await store.append(entry: fresh)

    let raw = try String(contentsOf: tmp, encoding: .utf8)
    #expect(!raw.contains("com.old"), "Pruned entry leaked to disk")
    #expect(raw.contains("com.fresh"), "Fresh entry missing from disk")
}

@Test("persistOnDisk=false: no file is written")
func historyInMemoryOnlyWritesNothing() async throws {
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("history-inmem-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: tmp) }

    let store = HistoryStore(
        storageURL: tmp,
        clipboardService: StubClipboardService(),
        persistOnDisk: false,
        retentionDays: 30
    )

    let e = TranscriptEntry(
        id: UUID(),
        createdAt: Date(),
        appBundleID: "com.stealth",
        rawText: "should not hit disk",
        cleanText: "should not hit disk",
        audioURL: nil,
        insertionStatus: .inserted
    )
    try await store.append(entry: e)

    #expect(
        !FileManager.default.fileExists(atPath: tmp.path),
        "persistOnDisk=false must never create the history file"
    )

    // In-memory retrieval still works for the live session.
    let recent = await store.recent(limit: 10)
    #expect(recent.count == 1)
}

@Test("setPersistOnDisk(false) removes any existing on-disk file")
func historyTogglingOffDeletesExistingFile() async throws {
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("history-toggle-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: tmp) }

    let store = HistoryStore(
        storageURL: tmp,
        clipboardService: StubClipboardService(),
        persistOnDisk: true,
        retentionDays: 30
    )
    let e = TranscriptEntry(
        id: UUID(),
        createdAt: Date(),
        appBundleID: "com.will.vanish",
        rawText: "before",
        cleanText: "before",
        audioURL: nil,
        insertionStatus: .inserted
    )
    try await store.append(entry: e)
    #expect(FileManager.default.fileExists(atPath: tmp.path))

    await store.setPersistOnDisk(false)
    #expect(
        !FileManager.default.fileExists(atPath: tmp.path),
        "Flipping persistence off must delete the on-disk file"
    )
}

@Test("On-disk history file is written with 0600 permissions")
func historyFilePermissions() async throws {
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("history-perms-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: tmp) }

    let store = HistoryStore(
        storageURL: tmp,
        clipboardService: StubClipboardService(),
        persistOnDisk: true,
        retentionDays: 30
    )
    try await store.append(entry: TranscriptEntry(
        id: UUID(),
        createdAt: Date(),
        appBundleID: "com.perm",
        rawText: "r",
        cleanText: "c",
        audioURL: nil,
        insertionStatus: .inserted
    ))

    let attrs = try FileManager.default.attributesOfItem(atPath: tmp.path)
    let perms = (attrs[.posixPermissions] as? NSNumber)?.int16Value ?? 0
    #expect(perms == 0o600, "Expected 0600, got octal \(String(perms, radix: 8))")
}

private final class StubClipboardService: ClipboardService, @unchecked Sendable {
    func setString(_ text: String) async throws {}
}
