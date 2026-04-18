import AVFoundation
import Foundation

public enum SessionCoordinatorError: Error, LocalizedError {
    case sessionNotFound

    public var errorDescription: String? {
        switch self {
        case .sessionNotFound:
            return "Session not found"
        }
    }
}

public actor SessionCoordinator {
    private struct ActiveSession: Sendable {
        var appContext: AppContext
        var startedAt: Date
    }

    private struct CleanupExecutionResult: Sendable {
        var transcript: CleanTranscript
        var outcome: CleanupOutcome
    }

    private let captureService: AudioCaptureService
    private let transcriptionEngine: TranscriptionEngine
    private let cleanupEngine: CleanupEngine
    private let fallbackCleanupEngine: CleanupEngine
    private let insertionService: InsertionServiceProtocol
    private let historyStore: HistoryStoreProtocol
    private let lexiconService: PersonalLexiconService
    private let styleProfileService: StyleProfileService
    private let snippetService: SnippetService

    private var activeSessions: [SessionID: ActiveSession] = [:]
    private(set) var isHandsFreeEnabled: Bool = false

    public init(
        captureService: AudioCaptureService,
        transcriptionEngine: TranscriptionEngine,
        cleanupEngine: CleanupEngine,
        insertionService: InsertionServiceProtocol,
        historyStore: HistoryStoreProtocol,
        lexiconService: PersonalLexiconService,
        styleProfileService: StyleProfileService,
        snippetService: SnippetService = SnippetService(),
        fallbackCleanupEngine: CleanupEngine = RuleBasedCleanupEngine()
    ) {
        self.captureService = captureService
        self.transcriptionEngine = transcriptionEngine
        self.cleanupEngine = cleanupEngine
        self.insertionService = insertionService
        self.historyStore = historyStore
        self.lexiconService = lexiconService
        self.styleProfileService = styleProfileService
        self.snippetService = snippetService
        self.fallbackCleanupEngine = fallbackCleanupEngine
    }

    @discardableResult
    public func startPressToTalk(appContext: AppContext) async throws -> SessionID {
        let sessionID = SessionID()
        try await captureService.beginCapture(sessionID: sessionID)
        activeSessions[sessionID] = ActiveSession(appContext: appContext, startedAt: Date())
        return sessionID
    }

    public func stopPressToTalk(sessionID: SessionID, languageMode: LanguageMode = .auto) async throws -> InsertResult {
        // Remove session before the first await so actor reentrancy cannot process
        // the same session twice while transcription/cleanup are in flight.
        guard let active = activeSessions.removeValue(forKey: sessionID) else {
            throw SessionCoordinatorError.sessionNotFound
        }

        let audioURL = try await captureService.endCapture(sessionID: sessionID)
        defer { try? FileManager.default.removeItem(at: audioURL) }

        // Drop clips too short to carry real speech. whisper.cpp on the
        // base model hallucinates wildly on sub-400ms input (typical
        // artifacts: "Okej" Swedish, "you" English, single-word Arabic).
        // Gate before calling whisper — saves 100-300ms and prevents
        // junk entries in history. duration==0 means the file couldn't
        // be read as audio (tests pass zero-byte stubs) — in that case
        // defer to the transcription engine's own handling.
        let durationSeconds = Self.audioDurationSeconds(url: audioURL)
        if durationSeconds > 0 && durationSeconds < 0.35 {
            return InsertResult(status: .noSpeech, method: .none, insertedText: "")
        }

        var rawTranscript = try await transcriptionEngine.transcribe(audioURL: audioURL, languageHints: [languageMode.rawValue])

        let trimmed = rawTranscript.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return InsertResult(status: .noSpeech, method: .none, insertedText: "")
        }

        // Post-hoc hallucination filter. whisper produces known
        // nonsense-from-silence phrases; if the clip was short AND the
        // output matches one of these, discard rather than insert.
        // durationSeconds==0 means test harness — don't filter there.
        if durationSeconds > 0 && durationSeconds < 1.6 && Self.isLikelyHallucination(trimmed) {
            return InsertResult(status: .noSpeech, method: .none, insertedText: "")
        }

        rawTranscript.text = await snippetService.apply(to: rawTranscript.text, appContext: active.appContext)

        let profile = await styleProfileService.resolve(for: active.appContext)
        let lexicon = await lexiconService.snapshot(for: active.appContext)

        let cleanupResult = try await prepareCleanTranscript(
            raw: rawTranscript,
            profile: profile,
            lexicon: lexicon,
            appContext: active.appContext
        )

        var insertResult = await insertionService.insert(text: cleanupResult.transcript.text, target: active.appContext)
        insertResult.cleanupOutcome = cleanupResult.outcome

        let entry = TranscriptEntry(
            appBundleID: active.appContext.bundleIdentifier,
            rawText: rawTranscript.text,
            cleanText: cleanupResult.transcript.text,
            // Audio artifacts are ephemeral; do not persist paths that are deleted on return.
            audioURL: nil,
            insertionStatus: insertResult.status
        )
        try await historyStore.append(entry: entry)

        return insertResult
    }

    public func cancel(sessionID: SessionID) async {
        activeSessions.removeValue(forKey: sessionID)
        await captureService.cancelCapture(sessionID: sessionID)
    }

    public func setHandsFreeEnabled(_ enabled: Bool) {
        isHandsFreeEnabled = enabled
    }

    private func prepareCleanTranscript(
        raw: RawTranscript,
        profile: StyleProfile,
        lexicon: PersonalLexicon,
        appContext: AppContext
    ) async throws -> CleanupExecutionResult {
        if profile.commandPolicy == .passthrough,
           appContext.isIDE,
           raw.text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("/") {
            return CleanupExecutionResult(
                transcript: CleanTranscript(text: raw.text),
                outcome: CleanupOutcome(source: .localOnly)
            )
        }

        do {
            let cleaned = try await cleanupEngine.cleanup(raw: raw, profile: profile, lexicon: lexicon)
            return CleanupExecutionResult(
                transcript: cleaned,
                outcome: CleanupOutcome(source: .localSuccess)
            )
        } catch {
            var fallback = try await fallbackCleanupEngine.cleanup(raw: raw, profile: profile, lexicon: lexicon)
            let warning = "Primary cleanup unavailable, used local fallback."
            fallback.uncertaintyFlags.append(warning)
            return CleanupExecutionResult(
                transcript: fallback,
                outcome: CleanupOutcome(source: .localFallback, warning: warning)
            )
        }
    }

    /// Known whisper hallucinations on silence / breath / click.
    /// Catalog is conservative — only phrases that are (a) extremely common
    /// whisper artifacts AND (b) short enough that a real user wouldn't
    /// have dictated them in under 1.6s. Matched case-insensitively on the
    /// trimmed transcript.
    private static let knownHallucinations: Set<String> = [
        // English
        "you", "you.", "thank you", "thank you.", "thanks for watching",
        "thanks for watching.", "bye", "bye.", "ok", "okay", "okay.",
        // Swedish hallucinations (whisper's "small talk" default on silence)
        "okej", "okej.", "okej tack", "tack", "tack.",
        // Arabic short-clip hallucinations
        "شكرا", "شكرا لكم", "نعم", "حسنا", "حارق", "حسناً", "لا",
        // Nordic/German drift
        "danke", "ja", "ja.", "nein",
        // Music / audio-placeholder tokens whisper emits on noise
        "[music]", "(music)", "[applause]", "(applause)",
        "[ موسيقى ]", "( موسيقى )"
    ]

    private static func isLikelyHallucination(_ text: String) -> Bool {
        let normalized = text.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if knownHallucinations.contains(normalized) { return true }
        // Catch trivial repeat loops like "you you you you" or "ok ok ok".
        let tokens = normalized
            .split(whereSeparator: { $0.isWhitespace || $0 == "." || $0 == "," })
            .map(String.init)
        if tokens.count >= 3,
           let first = tokens.first,
           tokens.allSatisfy({ $0 == first }),
           first.count <= 4 {
            return true
        }
        return false
    }

    private static func audioDurationSeconds(url: URL) -> Double {
        let asset = AVURLAsset(url: url)
        let seconds = CMTimeGetSeconds(asset.duration)
        return seconds.isFinite && seconds > 0 ? seconds : 0
    }
}
