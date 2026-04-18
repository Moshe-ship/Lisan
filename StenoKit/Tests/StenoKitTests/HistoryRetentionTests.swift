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

@Test("Retention: tightening retentionDays at runtime prunes immediately")
func historyTighteningRetentionPrunesNow() async throws {
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("history-tighten-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: tmp) }

    let store = HistoryStore(
        storageURL: tmp,
        clipboardService: StubClipboardService(),
        maxEntries: 500,
        persistOnDisk: true,
        retentionDays: 30
    )

    // Seed with entries at varying ages. All survive 30-day retention.
    let threeDaysAgo = TranscriptEntry(
        id: UUID(),
        createdAt: Date().addingTimeInterval(-3 * 86_400),
        appBundleID: "com.three",
        rawText: "three days", cleanText: "three days",
        audioURL: nil, insertionStatus: .inserted
    )
    let tenDaysAgo = TranscriptEntry(
        id: UUID(),
        createdAt: Date().addingTimeInterval(-10 * 86_400),
        appBundleID: "com.ten",
        rawText: "ten days", cleanText: "ten days",
        audioURL: nil, insertionStatus: .inserted
    )
    let twentyFiveDaysAgo = TranscriptEntry(
        id: UUID(),
        createdAt: Date().addingTimeInterval(-25 * 86_400),
        appBundleID: "com.twentyfive",
        rawText: "twentyfive", cleanText: "twentyfive",
        audioURL: nil, insertionStatus: .inserted
    )
    try await store.append(entry: twentyFiveDaysAgo)
    try await store.append(entry: tenDaysAgo)
    try await store.append(entry: threeDaysAgo)

    let before = await store.recent(limit: 100)
    #expect(before.count == 3, "All three entries should survive the initial 30-day window")

    // Tighten to 7 days. Entries older than that must disappear
    // immediately — in memory AND on disk.
    await store.setRetentionDays(7)

    let after = await store.recent(limit: 100)
    let afterIDs = Set(after.map { $0.appBundleID })
    #expect(afterIDs == ["com.three"],
            "Tightening to 7 days should drop 10-day and 25-day entries, got: \(afterIDs)")

    // Confirm the on-disk JSON reflects the pruning, not just memory.
    let raw = try String(contentsOf: tmp, encoding: .utf8)
    #expect(raw.contains("com.three"))
    #expect(!raw.contains("com.ten"), "10-day entry leaked to disk after tightening")
    #expect(!raw.contains("com.twentyfive"), "25-day entry leaked to disk after tightening")
}

@Test("Retention: widening retentionDays does not resurrect already-dropped entries")
func historyWideningDoesNotResurrectDropped() async throws {
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("history-widen-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: tmp) }

    let store = HistoryStore(
        storageURL: tmp,
        clipboardService: StubClipboardService(),
        maxEntries: 500,
        persistOnDisk: true,
        retentionDays: 3
    )

    // This entry is older than the initial 3-day window, so `append`
    // itself will immediately prune it during the pruneExpired call.
    try await store.append(entry: TranscriptEntry(
        id: UUID(),
        createdAt: Date().addingTimeInterval(-10 * 86_400),
        appBundleID: "com.lost",
        rawText: "lost", cleanText: "lost",
        audioURL: nil, insertionStatus: .inserted
    ))

    let beforeWiden = await store.recent(limit: 100)
    #expect(beforeWiden.isEmpty,
            "10-day-old entry should have been dropped under 3-day retention")

    // Widen to 30 days. The already-dropped entry must not come back —
    // pruning is destructive, not a filter, so widening is a no-op
    // against existing state.
    await store.setRetentionDays(30)
    let afterWiden = await store.recent(limit: 100)
    #expect(afterWiden.isEmpty,
            "Widening retention shouldn't resurrect entries already pruned")
}

@Test("Observability: setRetentionDays returns prune count for tightening")
func historyReturnsPruneCountOnTighten() async throws {
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("history-count-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: tmp) }

    let store = HistoryStore(
        storageURL: tmp,
        clipboardService: StubClipboardService(),
        maxEntries: 500,
        persistOnDisk: true,
        retentionDays: 30
    )

    // Two entries older than the new 7-day window, one inside it.
    for daysAgo in [10, 20, 2] {
        try await store.append(entry: TranscriptEntry(
            id: UUID(),
            createdAt: Date().addingTimeInterval(-Double(daysAgo) * 86_400),
            appBundleID: "com.age.\(daysAgo)",
            rawText: "r", cleanText: "c",
            audioURL: nil, insertionStatus: .inserted
        ))
    }

    let result = await store.setRetentionDays(7)
    #expect(result.prunedCount == 2, "Expected 2 pruned (the 10 and 20-day entries), got \(result.prunedCount)")
    #expect(result.persistError == nil, "Healthy disk write should not surface an error")
}

@Test("Observability: applyPreferences aggregates persist + retention into a single result")
func historyApplyPreferencesAggregates() async throws {
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("history-apply-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: tmp) }

    let store = HistoryStore(
        storageURL: tmp,
        clipboardService: StubClipboardService(),
        maxEntries: 500,
        persistOnDisk: true,
        retentionDays: 30
    )
    try await store.append(entry: TranscriptEntry(
        id: UUID(),
        createdAt: Date().addingTimeInterval(-25 * 86_400),
        appBundleID: "com.aged",
        rawText: "r", cleanText: "c",
        audioURL: nil, insertionStatus: .inserted
    ))

    let result = await store.applyPreferences(
        HistoryPreferences(persistOnDisk: true, retentionDays: 14)
    )
    #expect(result.prunedCount == 1)
    #expect(result.persistError == nil)
}

@Test("Legacy prune count: first-load prune is observable via consumeLegacyPruneCount()")
func historyLegacyPruneCount() async throws {
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("history-legacy-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: tmp) }

    // Seed the file as if a pre-retention build wrote 3 entries, one of
    // which would be outside the new default 30-day window.
    let prewritten: [TranscriptEntry] = [
        TranscriptEntry(
            id: UUID(),
            createdAt: Date().addingTimeInterval(-60 * 86_400),
            appBundleID: "com.very.old",
            rawText: "old", cleanText: "old",
            audioURL: nil, insertionStatus: .inserted
        ),
        TranscriptEntry(
            id: UUID(),
            createdAt: Date().addingTimeInterval(-5 * 86_400),
            appBundleID: "com.recent",
            rawText: "recent", cleanText: "recent",
            audioURL: nil, insertionStatus: .inserted
        ),
        TranscriptEntry(
            id: UUID(),
            createdAt: Date().addingTimeInterval(-1 * 86_400),
            appBundleID: "com.newest",
            rawText: "newest", cleanText: "newest",
            audioURL: nil, insertionStatus: .inserted
        ),
    ]
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    try encoder.encode(prewritten).write(to: tmp)

    let store = HistoryStore(
        storageURL: tmp,
        clipboardService: StubClipboardService(),
        maxEntries: 500,
        persistOnDisk: true,
        retentionDays: 30
    )

    // First consume reports pruned count. Second returns 0 (idempotent
    // single-session consumption).
    let first = await store.consumeLegacyPruneCount()
    #expect(first == 1, "Expected 1 legacy prune (the 60-day entry), got \(first)")
    let second = await store.consumeLegacyPruneCount()
    #expect(second == 0, "Counter should reset after first consume")
}

@Test("Observability: flipping persistOnDisk off reports clearedOnDiskCount")
func historyFlippingOffReportsClearedCount() async throws {
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("history-flip-count-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: tmp) }

    let store = HistoryStore(
        storageURL: tmp,
        clipboardService: StubClipboardService(),
        maxEntries: 500,
        persistOnDisk: true,
        retentionDays: 30
    )

    // Seed 3 entries, all in-window — they are on disk before the flip.
    for i in 0..<3 {
        try await store.append(entry: TranscriptEntry(
            id: UUID(),
            createdAt: Date(),
            appBundleID: "com.flip.\(i)",
            rawText: "r\(i)", cleanText: "c\(i)",
            audioURL: nil, insertionStatus: .inserted
        ))
    }
    #expect(FileManager.default.fileExists(atPath: tmp.path))

    let result = await store.setPersistOnDisk(false)
    #expect(
        result.clearedOnDiskCount == 3,
        "Expected clearedOnDiskCount = 3 (entries that were on disk), got \(String(describing: result.clearedOnDiskCount))"
    )
    #expect(!FileManager.default.fileExists(atPath: tmp.path),
            "File should have been removed")

    // Entries are still in memory even though the file is gone.
    let stillInMemory = await store.recent(limit: 100)
    #expect(stillInMemory.count == 3)
}

@Test("Observability: flipping persistOnDisk off with no file yields nil clearedOnDiskCount (no noise event)")
func historyFlippingOffWithNoFileYieldsNil() async throws {
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("history-flip-nofile-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: tmp) }

    // Start with persistence ON but never appended — no file exists.
    let store = HistoryStore(
        storageURL: tmp,
        clipboardService: StubClipboardService(),
        maxEntries: 500,
        persistOnDisk: true,
        retentionDays: 30
    )
    #expect(!FileManager.default.fileExists(atPath: tmp.path))

    let result = await store.setPersistOnDisk(false)
    #expect(
        result.clearedOnDiskCount == nil,
        "When no file existed to clear, clearedOnDiskCount must be nil so the caller skips the audit event"
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
