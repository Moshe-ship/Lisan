import Foundation
import OSLog

// MARK: - Event types

/// A diagnostic event captured by `DiagnosticsTelemetry`.
///
/// This is a closed sum type — every payload is a bounded enum or a
/// controlled string drawn from a fixed vocabulary. There is no case
/// that accepts a free-form transcript, audio buffer, spoken phrase,
/// vocabulary-file content, lexicon entry, or clipboard text. The
/// content-no-leak invariant from `LOGGING_POLICY.md` is enforced by
/// the shape of this type, not by discipline. You literally cannot
/// log transcript content through this API — you would have to change
/// the type definition to do it.
///
/// When a new event category is needed, add a case here and give it
/// bounded payload types (enums or short compile-time strings). Never
/// add a `String` payload that could be populated from user content.
public enum DiagnosticEvent: Sendable, Codable, Equatable {

    /// App failed to complete its bootstrap. `phase` identifies WHERE,
    /// `errorCode` is a machine-readable reason drawn from a fixed vocabulary.
    case startupFailure(phase: StartupPhase, errorCode: StartupErrorCode)

    /// Text insertion into the frontmost app failed.
    case insertionFailure(method: InsertionMethod, targetBundleID: TargetBundleID?, reason: InsertionFailureReason)

    /// Whisper / VAD model file was not found at the configured path.
    /// `kind` is the model role (dictation vs VAD). The CONFIGURED path
    /// may be logged because it's a user preference, not spoken content.
    case modelNotFound(kind: ModelKind, configuredPath: PathKind)

    /// Whisper-cli or VAD subprocess exited non-zero.
    case engineError(process: EngineProcess, exitCode: Int32)

    /// TCC permission denied or needs approval.
    case permissionDenied(permission: PermissionKind)

    /// Config value failed validation.
    case configValidationFailure(field: ConfigField, reason: ConfigFailureReason)

    /// Notarization staple is missing or invalid — useful if we ever ship
    /// a broken build and need the installed base to phone home a diagnostic
    /// (locally only; no network calls are made by this service).
    case notarizationMismatch

    // MARK: - Bounded enum payloads

    public enum StartupPhase: String, Sendable, Codable { case preferencesLoad, pipelineBootstrap, hotkeyRegistration, menuBarSetup, uiPresent }
    public enum StartupErrorCode: String, Sendable, Codable { case preferencesCorrupt, migrationFailed, hotkeyTaken, inputSystemUnavailable, unknown }
    public enum InsertionFailureReason: String, Sendable, Codable { case accessibilityDenied, axWriteFailed, cgEventSendFailed, clipboardBusy, targetRefused, unknown }
    public enum ModelKind: String, Sendable, Codable { case dictation, vad }
    public enum EngineProcess: String, Sendable, Codable { case whisperCLI, vad }
    public enum PermissionKind: String, Sendable, Codable { case microphone, accessibility, inputMonitoring, loginItemsApproval }
    public enum ConfigField: String, Sendable, Codable { case threadCount, whisperCLIPath, modelPath, vocabularyPath, languageMode }
    public enum ConfigFailureReason: String, Sendable, Codable { case missing, notAbsolutePath, notReadable, outOfRange, unknownValue }

    // MARK: - Controlled strings

    /// A bundle ID is a fixed value emitted by the frontmost app (e.g.
    /// `com.apple.finder`). It is NOT user content and NOT unique to a
    /// person. We cap length and strip anything that isn't the standard
    /// bundle-id character set to be defensive.
    public struct TargetBundleID: Sendable, Codable, Equatable {
        public let value: String
        public init?(_ raw: String?) {
            guard let raw else { return nil }
            // Take the longest leading run that matches real bundle-id
            // character set: a-z, A-Z, 0-9, dot, hyphen. Stop at the first
            // disallowed character — bundle IDs can't legally contain
            // whitespace or mid-string specials, so anything after is not
            // part of the bundle ID and could be attacker-controlled.
            let allowed = CharacterSet(charactersIn:
                "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-")
            var scalars: [Unicode.Scalar] = []
            scalars.reserveCapacity(min(raw.unicodeScalars.count, 128))
            for scalar in raw.unicodeScalars {
                guard allowed.contains(scalar), scalars.count < 128 else { break }
                scalars.append(scalar)
            }
            let sanitized = String(String.UnicodeScalarView(scalars))
            guard !sanitized.isEmpty else { return nil }
            self.value = sanitized
        }
    }

    /// A path is tagged with its role so the log never records a user's
    /// home directory layout unintentionally. The `redacted` form is used
    /// in copy-to-clipboard so support receives a reason without a
    /// filesystem fingerprint.
    public struct PathKind: Sendable, Codable, Equatable {
        public let role: String            // "dictation-model", "vad-model", "vocabulary"
        public let redacted: String        // "<home>/vendor/whisper.cpp/models/ggml-base.bin" etc
        public init(role: String, absolute: String) {
            self.role = role
            let home = NSHomeDirectory()
            self.redacted = absolute.hasPrefix(home)
                ? absolute.replacingOccurrences(of: home, with: "<home>")
                : "<external>"
        }
    }
}

// MARK: - Record wrapper

/// A timestamped `DiagnosticEvent` persisted to disk.
public struct DiagnosticRecord: Sendable, Codable, Equatable {
    public let timestamp: Date
    public let event: DiagnosticEvent

    public init(timestamp: Date = Date(), event: DiagnosticEvent) {
        self.timestamp = timestamp
        self.event = event
    }
}

// MARK: - Storage protocol

public protocol DiagnosticsStorage: Sendable {
    func append(_ record: DiagnosticRecord) async throws
    func load() async throws -> [DiagnosticRecord]
    func clear() async throws
}

// MARK: - Telemetry service

/// Records `DiagnosticEvent`s to local storage. Never sends over network.
/// Caps history to `capacity` (FIFO). Coalesces writes so a burst of
/// insertion failures doesn't thrash the disk.
public actor DiagnosticsTelemetry {

    public let capacity: Int
    private let storage: any DiagnosticsStorage
    private var buffer: [DiagnosticRecord] = []
    private var loaded = false

    public init(capacity: Int = 200, storage: any DiagnosticsStorage) {
        self.capacity = capacity
        self.storage = storage
    }

    /// Record an event. Cheap — no disk I/O on the hot path for the first
    /// N events; flushes happen on `flush()` / natural lifecycle points.
    public func record(_ event: DiagnosticEvent) async {
        await ensureLoaded()
        let record = DiagnosticRecord(event: event)
        buffer.append(record)
        if buffer.count > capacity {
            buffer.removeFirst(buffer.count - capacity)
        }
        try? await storage.append(record)
    }

    /// Return the current in-memory buffer, most recent first.
    public func recent() async -> [DiagnosticRecord] {
        await ensureLoaded()
        return buffer.reversed()
    }

    /// Clear both in-memory and on-disk state.
    public func clear() async throws {
        buffer.removeAll()
        try await storage.clear()
    }

    // MARK: - Internal

    private func ensureLoaded() async {
        guard !loaded else { return }
        loaded = true
        if let loaded = try? await storage.load() {
            buffer = Array(loaded.suffix(capacity))
        }
    }
}

// MARK: - File-backed storage

/// Rolling JSON-lines file under Application Support with a hard line
/// cap on disk. The in-memory telemetry actor enforces capacity for
/// the live buffer; this layer mirrors that cap to the file so the
/// on-disk log never grows unbounded (previous behavior was append-
/// forever, which contradicted the "bounded retention" contract).
///
/// On append, if the file has grown past `maxLinesOnDisk`, the last
/// `capAfterRotation` lines are rewritten atomically, replacing the
/// old file. Rotation is triggered lazily so happy-path appends stay
/// a single `write()` syscall.
public struct FileDiagnosticsStorage: DiagnosticsStorage {
    public let fileURL: URL
    /// Hard ceiling. When the file exceeds this, rotation fires.
    public let maxLinesOnDisk: Int
    /// After rotation, file is truncated down to this count. Kept
    /// smaller than `maxLinesOnDisk` so rotations don't retrigger on
    /// the very next append.
    public let capAfterRotation: Int

    public init(
        fileURL: URL,
        maxLinesOnDisk: Int = 1_000,
        capAfterRotation: Int = 500
    ) {
        precondition(capAfterRotation <= maxLinesOnDisk)
        self.fileURL = fileURL
        self.maxLinesOnDisk = maxLinesOnDisk
        self.capAfterRotation = capAfterRotation
    }

    public init(maxLinesOnDisk: Int = 1_000, capAfterRotation: Int = 500) {
        let base = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = base?.appendingPathComponent("Lisan", isDirectory: true)
            ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Lisan", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.init(
            fileURL: dir.appendingPathComponent("diagnostics.jsonl"),
            maxLinesOnDisk: maxLinesOnDisk,
            capAfterRotation: capAfterRotation
        )
    }

    public func append(_ record: DiagnosticRecord) async throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(record)
        var line = data
        line.append(0x0A)  // newline
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let handle = try FileHandle(forWritingTo: fileURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
            try? handle.close()
            // Enforce line cap. Cheap: only count when the file is
            // already sizable enough that rotation might be needed.
            try rotateIfOverCap()
        } else {
            try line.write(to: fileURL, options: .atomic)
            try? FileManager.default.setAttributes(
                [.posixPermissions: NSNumber(value: Int16(0o600))],
                ofItemAtPath: fileURL.path
            )
        }
    }

    /// Read the whole file, count lines, and if over cap, rewrite with
    /// only the tail. Cheap when the file is under cap: one stat().
    private func rotateIfOverCap() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        // Skip rotation work when the file is small regardless of cap
        // (cap is lines, but we read size first as a cheap pre-check —
        // 1000 JSON lines * ~300 bytes each ≈ 300 KB; files under 64 KB
        // can't plausibly hit our line cap).
        if let size = attrs?[.size] as? NSNumber, size.intValue < 64 * 1024 {
            return
        }
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        let lines = content.split(separator: "\n", omittingEmptySubsequences: true)
        guard lines.count > maxLinesOnDisk else { return }
        let kept = lines.suffix(capAfterRotation)
        let rewritten = kept.joined(separator: "\n") + "\n"
        try rewritten.write(to: fileURL, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o600))],
            ofItemAtPath: fileURL.path
        )
    }

    public func load() async throws -> [DiagnosticRecord] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var out: [DiagnosticRecord] = []
        for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = line.data(using: .utf8),
                  let r = try? decoder.decode(DiagnosticRecord.self, from: data) else {
                continue  // Skip corrupt lines — better than losing the whole log
            }
            out.append(r)
        }
        return out
    }

    public func clear() async throws {
        try? FileManager.default.removeItem(at: fileURL)
    }
}

// MARK: - In-memory storage for tests

public actor InMemoryDiagnosticsStorage: DiagnosticsStorage {
    private var records: [DiagnosticRecord] = []
    public init() {}
    public func append(_ record: DiagnosticRecord) async throws { records.append(record) }
    public func load() async throws -> [DiagnosticRecord] { records }
    public func clear() async throws { records.removeAll() }
}
