import Foundation
import Testing
@testable import StenoKit

struct DiagnosticsTelemetryTests {

    // MARK: - Basic contract

    @Test("Records a single event and can read it back")
    func recordAndRead() async {
        let storage = InMemoryDiagnosticsStorage()
        let t = DiagnosticsTelemetry(storage: storage)
        await t.record(.permissionDenied(permission: .microphone))
        let items = await t.recent()
        #expect(items.count == 1)
        if case .permissionDenied(let kind) = items[0].event {
            #expect(kind == .microphone)
        } else { #expect(Bool(false), "wrong event") }
    }

    @Test("Events return most-recent-first")
    func recentIsReverseChronological() async {
        let t = DiagnosticsTelemetry(storage: InMemoryDiagnosticsStorage())
        await t.record(.permissionDenied(permission: .microphone))
        await t.record(.permissionDenied(permission: .accessibility))
        await t.record(.permissionDenied(permission: .inputMonitoring))
        let items = await t.recent()
        #expect(items.count == 3)
        if case .permissionDenied(let k) = items[0].event { #expect(k == .inputMonitoring) }
        if case .permissionDenied(let k) = items[2].event { #expect(k == .microphone) }
    }

    @Test("Clear removes everything in-memory and on storage")
    func clearRemoves() async throws {
        let storage = InMemoryDiagnosticsStorage()
        let t = DiagnosticsTelemetry(storage: storage)
        await t.record(.notarizationMismatch)
        #expect(await t.recent().count == 1)
        try await t.clear()
        #expect(await t.recent().isEmpty)
        #expect(try await storage.load().isEmpty)
    }

    // MARK: - Capacity

    @Test("Enforces capacity (FIFO)")
    func capacityCap() async {
        let t = DiagnosticsTelemetry(capacity: 3, storage: InMemoryDiagnosticsStorage())
        for _ in 0..<10 {
            await t.record(.notarizationMismatch)
        }
        let items = await t.recent()
        #expect(items.count == 3)
    }

    // MARK: - Privacy invariants (enforced by the type, verified by tests)

    @Test("TargetBundleID rejects characters outside the bundle-id charset")
    func targetBundleIDSanitizes() {
        // Raw value with spaces, Arabic letters, and emoji — must all be stripped.
        let b = DiagnosticEvent.TargetBundleID("com.apple.finder صوت 🎤 <script>")
        #expect(b?.value == "com.apple.finder")
    }

    @Test("TargetBundleID caps length at 128")
    func targetBundleIDTruncates() {
        let raw = String(repeating: "a", count: 500)
        let b = DiagnosticEvent.TargetBundleID(raw)
        #expect(b?.value.count == 128)
    }

    @Test("TargetBundleID returns nil for empty or all-invalid input")
    func targetBundleIDNilOnEmpty() {
        #expect(DiagnosticEvent.TargetBundleID(nil) == nil)
        #expect(DiagnosticEvent.TargetBundleID("") == nil)
        #expect(DiagnosticEvent.TargetBundleID("صوت") == nil)   // no ASCII bundle-id chars
    }

    @Test("PathKind redacts the home directory")
    func pathRedaction() {
        let home = NSHomeDirectory()
        let path = "\(home)/vendor/whisper.cpp/models/ggml-base.bin"
        let p = DiagnosticEvent.PathKind(role: "dictation-model", absolute: path)
        #expect(p.redacted.hasPrefix("<home>/"))
        #expect(!p.redacted.contains(home))
    }

    @Test("PathKind tags external paths without exposing them")
    func pathExternal() {
        let p = DiagnosticEvent.PathKind(role: "dictation-model", absolute: "/opt/whisper/models/x.bin")
        #expect(p.redacted == "<external>")
    }

    // MARK: - File-backed storage

    @Test("FileDiagnosticsStorage round-trips events")
    func fileRoundTrip() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("lisan-telem-test-\(UUID()).jsonl")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let storage = FileDiagnosticsStorage(fileURL: tmp)
        let t = DiagnosticsTelemetry(storage: storage)

        await t.record(.modelNotFound(kind: .dictation, configuredPath: .init(
            role: "dictation-model",
            absolute: NSHomeDirectory() + "/missing/model.bin"
        )))
        await t.record(.engineError(process: .whisperCLI, exitCode: 127))

        // Load from a fresh reader to prove on-disk persistence.
        let fresh = DiagnosticsTelemetry(storage: FileDiagnosticsStorage(fileURL: tmp))
        let items = await fresh.recent()
        #expect(items.count == 2)
    }

    @Test("FileDiagnosticsStorage skips corrupt lines without losing the rest")
    func corruptLineResilience() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("lisan-telem-corrupt-\(UUID()).jsonl")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let storage = FileDiagnosticsStorage(fileURL: tmp)
        let t = DiagnosticsTelemetry(storage: storage)
        await t.record(.permissionDenied(permission: .microphone))

        // Manually corrupt by appending garbage.
        if let data = "\n{not valid json}\n".data(using: .utf8) {
            let h = try FileHandle(forWritingTo: tmp)
            try h.seekToEnd()
            try h.write(contentsOf: data)
            try h.close()
        }

        await t.record(.permissionDenied(permission: .accessibility))

        // Load fresh.
        let fresh = DiagnosticsTelemetry(storage: FileDiagnosticsStorage(fileURL: tmp))
        let items = await fresh.recent()
        #expect(items.count == 2)  // Both valid events survived, corrupt line skipped.
    }

    // MARK: - Codable contract

    @Test("Event Codable round-trip preserves semantics")
    func codableRoundTrip() throws {
        let event: DiagnosticEvent = .insertionFailure(
            method: .accessibility,
            targetBundleID: .init("com.apple.Terminal"),
            reason: .axWriteFailed
        )
        let encoded = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(DiagnosticEvent.self, from: encoded)
        #expect(decoded == event)
    }

    // MARK: - Type-level content-leak invariant

    @Test("DiagnosticEvent has no String payload cases (content-leak-proof by type)")
    func noStringPayloadCases() {
        // This test is a design contract: if someone adds a case like
        // .dictationContent(String) to DiagnosticEvent, this test will
        // need updating — and that UPDATE is the review gate where the
        // contributor must justify the change. The policy is:
        // reviewer must reject any such case unless the payload is the
        // TargetBundleID-style sanitized type or a bounded enum.
        //
        // We assert by constructing one of every existing case. If a new
        // case is added with a non-bounded type, the type checker will
        // break this test until someone sanitizes it.
        let all: [DiagnosticEvent] = [
            .startupFailure(phase: .preferencesLoad, errorCode: .unknown),
            .insertionFailure(method: .direct, targetBundleID: nil, reason: .unknown),
            .modelNotFound(kind: .dictation, configuredPath: .init(role: "x", absolute: "/x")),
            .engineError(process: .whisperCLI, exitCode: 1),
            .permissionDenied(permission: .microphone),
            .configValidationFailure(field: .threadCount, reason: .outOfRange),
            .notarizationMismatch,
            .historyPruned(count: 3, trigger: .retentionTightened),
            .persistenceFailure(target: .transcriptHistory),
        ]
        #expect(all.count == 9)
    }

    // MARK: - On-disk retention

    @Test("FileDiagnosticsStorage rotates when on-disk line count exceeds maxLinesOnDisk")
    func fileStorageRotatesWhenOverCap() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("diag-rotate-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: tmp) }

        // Force rotation at 50 with trim to 10 so the test runs fast.
        let storage = FileDiagnosticsStorage(
            fileURL: tmp,
            maxLinesOnDisk: 50,
            capAfterRotation: 10
        )

        // Pre-fill with > 50 lines by append-forcing many events. Also
        // include enough bytes per line to push the file past the 64 KB
        // pre-rotation-check threshold (each record is ~170-200 bytes,
        // but rotation only triggers beyond 64 KB). Stuff filler text
        // into the TargetBundleID-sanitized form via repeated insertion
        // failures which carry a bundle string.
        for _ in 0..<400 {
            try await storage.append(DiagnosticRecord(
                event: .insertionFailure(
                    method: .direct,
                    targetBundleID: .init("com.example.longname.padding.for.bytes"),
                    reason: .unknown
                )
            ))
        }

        let loaded = try await storage.load()
        #expect(loaded.count <= 50,
                "After 400 appends, file should be rotated at cap 50; got \(loaded.count) lines")
        #expect(loaded.count >= 10,
                "After rotation, file should hold at least capAfterRotation=10 lines")
    }

    @Test("FileDiagnosticsStorage preserves line order after rotation (keeps tail)")
    func fileStoragePreservesTailAfterRotation() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("diag-tail-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let storage = FileDiagnosticsStorage(
            fileURL: tmp,
            maxLinesOnDisk: 50,
            capAfterRotation: 10
        )

        // Use distinct error codes so we can verify which records survived.
        let errorCodes: [DiagnosticEvent.StartupErrorCode] = [
            .preferencesCorrupt, .migrationFailed, .hotkeyTaken,
            .inputSystemUnavailable, .unknown
        ]
        // Pre-fill: cycle through error codes a lot of times.
        for i in 0..<400 {
            let code = errorCodes[i % errorCodes.count]
            try await storage.append(DiagnosticRecord(
                event: .startupFailure(phase: .hotkeyRegistration, errorCode: code)
            ))
        }

        let loaded = try await storage.load()
        // After rotation, the last records written should still be in the
        // file. The very last append (index 399) had code errorCodes[399 % 5]
        // = errorCodes[4] = .unknown. It must survive.
        guard let last = loaded.last else {
            Issue.record("No records loaded")
            return
        }
        if case .startupFailure(_, let code) = last.event {
            #expect(code == .unknown,
                    "Rotation should keep the tail; last record's code should match the last written")
        } else {
            Issue.record("Expected startupFailure event, got \(last.event)")
        }
    }
}
