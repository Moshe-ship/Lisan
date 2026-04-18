import Foundation
import Testing
@testable import StenoKit

struct WhisperCLITranscriptionEngineTests {
    // MARK: - Original tests (preserved)

    @Test("WhisperCLITranscriptionEngine reads txt output on success")
    func whisperCLITranscriptionEngineSuccess() async throws {
        let scriptURL = try makeExecutableScript(
            """
            #!/bin/sh
            output_base=""
            while [ "$#" -gt 0 ]; do
              if [ "$1" = "-of" ]; then
                shift
                output_base="$1"
              fi
              shift
            done
            if [ -z "$output_base" ]; then
              echo "missing -of" >&2
              exit 2
            fi
            printf " hello from fake whisper \\n" > "${output_base}.txt"
            exit 0
            """
        )
        defer { try? FileManager.default.removeItem(at: scriptURL) }

        let audioURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("audio-\(UUID().uuidString).wav")
        try Data().write(to: audioURL)
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let engine = WhisperCLITranscriptionEngine(
            config: .init(
                whisperCLIPath: scriptURL,
                modelPath: URL(fileURLWithPath: "/tmp/fake-model.bin")
            )
        )

        let result = try await engine.transcribe(audioURL: audioURL, languageHints: ["en-US"])
        #expect(result.text == "hello from fake whisper")
    }

    @Test("WhisperCLITranscriptionEngine maps non-zero exits to failedToRun")
    func whisperCLITranscriptionEngineFailureExitCode() async throws {
        let scriptURL = try makeExecutableScript(
            """
            #!/bin/sh
            echo "boom failure" >&2
            exit 42
            """
        )
        defer { try? FileManager.default.removeItem(at: scriptURL) }

        let audioURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("audio-\(UUID().uuidString).wav")
        try Data().write(to: audioURL)
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let engine = WhisperCLITranscriptionEngine(
            config: .init(
                whisperCLIPath: scriptURL,
                modelPath: URL(fileURLWithPath: "/tmp/fake-model.bin")
            )
        )

        do {
            _ = try await engine.transcribe(audioURL: audioURL, languageHints: ["en"])
            Issue.record("Expected non-zero exit to throw failedToRun.")
        } catch WhisperCLITranscriptionError.failedToRun(let status, let stderr) {
            #expect(status == 42)
            #expect(stderr.contains("boom failure"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("WhisperCLITranscriptionEngine throws outputMissing when txt is absent")
    func whisperCLITranscriptionEngineMissingOutput() async throws {
        let scriptURL = try makeExecutableScript(
            """
            #!/bin/sh
            exit 0
            """
        )
        defer { try? FileManager.default.removeItem(at: scriptURL) }

        let audioURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("audio-\(UUID().uuidString).wav")
        try Data().write(to: audioURL)
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let engine = WhisperCLITranscriptionEngine(
            config: .init(
                whisperCLIPath: scriptURL,
                modelPath: URL(fileURLWithPath: "/tmp/fake-model.bin")
            )
        )

        do {
            _ = try await engine.transcribe(audioURL: audioURL, languageHints: ["en"])
            Issue.record("Expected missing output to throw outputMissing.")
        } catch WhisperCLITranscriptionError.outputMissing {
            // Expected.
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("WhisperCLITranscriptionEngine cancellation escalates when child ignores SIGTERM")
    func whisperCLITranscriptionEngineCancellationEscalation() async throws {
        let scriptURL = try makeExecutableScript(
            """
            #!/bin/sh
            trap '' TERM
            while :; do
              sleep 1
            done
            """
        )
        defer { try? FileManager.default.removeItem(at: scriptURL) }

        let audioURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("audio-\(UUID().uuidString).wav")
        try Data().write(to: audioURL)
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let engine = WhisperCLITranscriptionEngine(
            config: .init(
                whisperCLIPath: scriptURL,
                modelPath: URL(fileURLWithPath: "/tmp/fake-model.bin")
            )
        )

        let task = Task {
            try await engine.transcribe(audioURL: audioURL, languageHints: ["en"])
        }

        try await Task.sleep(nanoseconds: 120_000_000)
        task.cancel()
        let cancellationStart = Date()

        do {
            _ = try await awaitTaskValue(task, timeoutNanoseconds: 6_000_000_000)
            Issue.record("Expected cancellation to throw.")
        } catch is CancellationError {
            let elapsed = Date().timeIntervalSince(cancellationStart)
            #expect(elapsed < 6.0)
        } catch is TaskValueTimeoutError {
            Issue.record("Cancellation did not complete within timeout.")
        } catch {
            Issue.record("Expected CancellationError, got: \(error)")
        }
    }

    // MARK: - LanguageMode tests

    @Test("LanguageMode en emits -l en to whisper-cli")
    func languageModeENPassesLArg() async throws {
        let (scriptURL, captureID) = try makeLanguageCaptureScript()
        defer { try? FileManager.default.removeItem(at: scriptURL) }

        let audioURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("audio-\(UUID().uuidString).wav")
        try Data().write(to: audioURL)
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let engine = WhisperCLITranscriptionEngine(
            config: .init(whisperCLIPath: scriptURL, modelPath: URL(fileURLWithPath: "/tmp/fake.bin"))
        )

        _ = try await engine.transcribe(audioURL: audioURL, languageHints: [LanguageMode.en.rawValue])
        let captured = try String(
            contentsOf: URL(fileURLWithPath: "/tmp/captured_args_\(captureID).txt"),
            encoding: .utf8
        )
        #expect(captured.contains("-l"), "en mode should emit -l")
        #expect(captured.contains("en"), "en mode should pass en as language code")
    }

    @Test("LanguageMode ar emits -l ar to whisper-cli")
    func languageModeARPassesLArg() async throws {
        let (scriptURL, captureID) = try makeLanguageCaptureScript()
        defer { try? FileManager.default.removeItem(at: scriptURL) }

        let audioURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("audio-\(UUID().uuidString).wav")
        try Data().write(to: audioURL)
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let engine = WhisperCLITranscriptionEngine(
            config: .init(whisperCLIPath: scriptURL, modelPath: URL(fileURLWithPath: "/tmp/fake.bin"))
        )

        _ = try await engine.transcribe(audioURL: audioURL, languageHints: [LanguageMode.ar.rawValue])
        let captured = try String(
            contentsOf: URL(fileURLWithPath: "/tmp/captured_args_\(captureID).txt"),
            encoding: .utf8
        )
        #expect(captured.contains("-l"), "ar mode should emit -l")
        #expect(captured.contains("ar"), "ar mode should pass ar as language code")
    }

    @Test("LanguageMode auto emits -l auto (whisper default -l is en, not auto)")
    func languageModeAutoEmitsAuto() async throws {
        let (scriptURL, captureID) = try makeLanguageCaptureScript()
        defer { try? FileManager.default.removeItem(at: scriptURL) }

        let audioURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("audio-\(UUID().uuidString).wav")
        try Data().write(to: audioURL)
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let engine = WhisperCLITranscriptionEngine(
            config: .init(whisperCLIPath: scriptURL, modelPath: URL(fileURLWithPath: "/tmp/fake.bin"))
        )

        _ = try await engine.transcribe(audioURL: audioURL, languageHints: [LanguageMode.auto.rawValue])
        let captured = try String(
            contentsOf: URL(fileURLWithPath: "/tmp/captured_args_\(captureID).txt"),
            encoding: .utf8
        )
        #expect(captured.contains("-l"), "auto mode must emit -l (whisper's -l default is en, not auto)")
        #expect(captured.contains("auto"), "auto mode must pass 'auto' as the language code to enable detection")
    }

    // MARK: - Two-pass auto-detect tests

    @Test("Two-pass auto-detect: -dl preflight result replaces -l auto when recognized")
    func twoPassDetectReplacesAuto() async throws {
        let captureID = UUID().uuidString
        let captureFile = "/tmp/captured_two_pass_args_\(captureID).txt"
        defer { try? FileManager.default.removeItem(atPath: captureFile) }

        // Fake whisper-cli: first invocation uses -dl and emits a known
        // "auto-detected language: ar" stderr line. Second invocation
        // captures its args so the test can verify -l ar was passed.
        let scriptURL = try makeExecutableScript(
            """
            #!/bin/sh
            all_args="$*"
            output_base=""
            saw_dl=0
            while [ "$#" -gt 0 ]; do
              case "$1" in
                -of) shift; output_base="$1" ;;
                -dl) saw_dl=1 ;;
              esac
              shift
            done
            if [ "$saw_dl" -eq 1 ]; then
              echo "whisper_full: auto-detected language: ar (p = 0.88)" >&2
              exit 0
            fi
            printf "%s" "$all_args" > \(captureFile)
            printf " hello arabic \\n" > "${output_base}.txt"
            exit 0
            """
        )
        defer { try? FileManager.default.removeItem(at: scriptURL) }

        let audioURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("audio-\(UUID().uuidString).wav")
        try Data().write(to: audioURL)
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let engine = WhisperCLITranscriptionEngine(
            config: .init(
                whisperCLIPath: scriptURL,
                modelPath: URL(fileURLWithPath: "/tmp/fake.bin"),
                twoPassAutoDetect: true
            )
        )

        _ = try await engine.transcribe(audioURL: audioURL, languageHints: [LanguageMode.auto.rawValue])

        let captured = try String(contentsOf: URL(fileURLWithPath: captureFile), encoding: .utf8)
        #expect(captured.contains("-l ar"), "Two-pass mode should forward detected 'ar' as -l ar on the real decode")
        #expect(!captured.contains("-l auto"), "When preflight detects ar, -l auto must NOT appear on the real decode")
    }

    @Test("Two-pass auto-detect: unknown preflight result falls back to -l auto")
    func twoPassDetectFallsBackOnUnknown() async throws {
        let captureID = UUID().uuidString
        let captureFile = "/tmp/captured_two_pass_args_\(captureID).txt"
        defer { try? FileManager.default.removeItem(atPath: captureFile) }

        // Preflight says "sv" (Swedish) — typical misfire on noise. Our
        // allow-list only forces en/ar; everything else becomes -l auto
        // so the decoder isn't locked into a wrong language.
        let scriptURL = try makeExecutableScript(
            """
            #!/bin/sh
            all_args="$*"
            output_base=""
            saw_dl=0
            while [ "$#" -gt 0 ]; do
              case "$1" in
                -of) shift; output_base="$1" ;;
                -dl) saw_dl=1 ;;
              esac
              shift
            done
            if [ "$saw_dl" -eq 1 ]; then
              echo "whisper_full: auto-detected language: sv (p = 0.31)" >&2
              exit 0
            fi
            printf "%s" "$all_args" > \(captureFile)
            printf " fallback \\n" > "${output_base}.txt"
            exit 0
            """
        )
        defer { try? FileManager.default.removeItem(at: scriptURL) }

        let audioURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("audio-\(UUID().uuidString).wav")
        try Data().write(to: audioURL)
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let engine = WhisperCLITranscriptionEngine(
            config: .init(
                whisperCLIPath: scriptURL,
                modelPath: URL(fileURLWithPath: "/tmp/fake.bin"),
                twoPassAutoDetect: true
            )
        )

        _ = try await engine.transcribe(audioURL: audioURL, languageHints: [LanguageMode.auto.rawValue])

        let captured = try String(contentsOf: URL(fileURLWithPath: captureFile), encoding: .utf8)
        #expect(captured.contains("-l auto"), "Unknown preflight detections must fall back to -l auto on the real decode")
        #expect(!captured.contains("-l sv"), "Swedish detections must not be forced — allow-list protects against noise misfires")
    }

    @Test("Two-pass auto-detect: disabled by default, single -dl never runs")
    func twoPassDisabledByDefault() async throws {
        let captureID = UUID().uuidString
        let captureFile = "/tmp/captured_single_pass_args_\(captureID).txt"
        defer { try? FileManager.default.removeItem(atPath: captureFile) }

        let scriptURL = try makeExecutableScript(
            """
            #!/bin/sh
            output_base=""
            for arg in "$@"; do
              if [ "$arg" = "-dl" ]; then
                echo "UNEXPECTED: -dl was passed" >&2
                exit 99
              fi
            done
            while [ "$#" -gt 0 ]; do
              if [ "$1" = "-of" ]; then shift; output_base="$1"; fi
              shift
            done
            printf "%s " "$@" > \(captureFile)
            printf " single pass \\n" > "${output_base}.txt"
            exit 0
            """
        )
        defer { try? FileManager.default.removeItem(at: scriptURL) }

        let audioURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("audio-\(UUID().uuidString).wav")
        try Data().write(to: audioURL)
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let engine = WhisperCLITranscriptionEngine(
            config: .init(
                whisperCLIPath: scriptURL,
                modelPath: URL(fileURLWithPath: "/tmp/fake.bin")
                // twoPassAutoDetect defaults to false
            )
        )

        let result = try await engine.transcribe(audioURL: audioURL, languageHints: [LanguageMode.auto.rawValue])
        #expect(result.text == "single pass")
    }

    // MARK: - Vocabulary file tests

    @Test("Vocabulary file content is space-joined and passed as --prompt")
    func vocabularyFilePassedAsPrompt() async throws {
        // Use a single UUID for both vocab file and prompt capture file
        let captureID = UUID().uuidString
        let vocabFileName = "vocab-\(captureID).txt"
        let vocabURL = URL(fileURLWithPath: "/tmp/").appendingPathComponent(vocabFileName)
        try "ماجدة\nOpenClaw\nNashir".write(to: vocabURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: vocabURL) }

        let (scriptURL, _) = try makePromptCaptureScript(captureID: captureID)
        defer { try? FileManager.default.removeItem(at: scriptURL) }

        let audioURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("audio-\(UUID().uuidString).wav")
        try Data().write(to: audioURL)
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let engine = WhisperCLITranscriptionEngine(
            config: .init(whisperCLIPath: scriptURL, modelPath: URL(fileURLWithPath: "/tmp/fake.bin")),
            vocabularyFileURL: vocabURL
        )

        _ = try await engine.transcribe(audioURL: audioURL, languageHints: ["en"])
        let captured = try String(
            contentsOf: URL(fileURLWithPath: "/tmp/captured_prompt_\(captureID).txt"),
            encoding: .utf8
        )
        #expect(captured.contains("ماجدة"), "Arabic proper noun should appear in prompt")
        #expect(captured.contains("OpenClaw"), "Latin terms should appear in prompt")
        #expect(captured.contains("Nashir"), "Transliteration should appear in prompt")
        // The printf '%s\n' always appends a trailing \n, so check the embedded content
        let contentWithoutTrailingNewline = String(captured.dropLast())
        #expect(!contentWithoutTrailingNewline.contains("\n"), "vocab content should be space-joined, no embedded newlines")
    }

    @Test("Missing vocabulary file does not throw; engine still produces output")
    func missingVocabularyFileDoesNotThrow() async throws {
        let scriptURL = try makeExecutableScript(
            """
            #!/bin/sh
            output_base=""
            while [ "$#" -gt 0 ]; do
              if [ "$1" = "-of" ]; then shift; output_base="$1"; fi
              shift
            done
            printf "ok\n" > "${output_base}.txt"
            exit 0
            """
        )
        defer { try? FileManager.default.removeItem(at: scriptURL) }

        let audioURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("audio-\(UUID().uuidString).wav")
        try Data().write(to: audioURL)
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let engine = WhisperCLITranscriptionEngine(
            config: .init(whisperCLIPath: scriptURL, modelPath: URL(fileURLWithPath: "/tmp/fake.bin")),
            vocabularyFileURL: URL(fileURLWithPath: "/tmp/nonexistent-vocab-\(UUID().uuidString).txt")
        )

        let result = try await engine.transcribe(audioURL: audioURL, languageHints: ["en"])
        #expect(result.text == "ok")
    }
}

// MARK: - Test helpers

private struct TaskValueTimeoutError: Error {}

private func awaitTaskValue<T>(
    _ task: Task<T, Error>,
    timeoutNanoseconds: UInt64
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await task.value
        }
        group.addTask {
            try await Task.sleep(nanoseconds: timeoutNanoseconds)
            task.cancel()
            throw TaskValueTimeoutError()
        }
        guard let value = try await group.next() else {
            throw TaskValueTimeoutError()
        }
        group.cancelAll()
        return value
    }
}

/// Creates a fake whisper-cli stub that exits 0 and writes fake output.
/// Returns the script URL.
private func makeExecutableScript(_ body: String) throws -> URL {
    let id = UUID().uuidString
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("fake-whisper-\(id).sh")
    try body.write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: Int16(0o755))], ofItemAtPath: url.path)
    return url
}

/// Creates a fake whisper-cli that captures all CLI args to /tmp/captured_args_<id>.txt
/// Returns (scriptURL, captureID).
private func makeLanguageCaptureScript() throws -> (URL, String) {
    let id = UUID().uuidString
    let script = """
    #!/bin/sh
    printf "%s\\n" "$@" > /tmp/captured_args_\(id).txt
    output_base=""
    while [ "$#" -gt 0 ]; do
      if [ "$1" = "-of" ]; then shift; output_base="$1"; fi
      shift
    done
    printf "result\\n" > "${output_base}.txt"
    exit 0
    """
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("fake-whisper-\(id).sh")
    try script.write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: Int16(0o755))], ofItemAtPath: url.path)
    return (url, id)
}

/// Creates a fake whisper-cli that captures the --prompt arg value to
/// /tmp/captured_prompt_<id>.txt. Returns (scriptURL, captureID).
private func makePromptCaptureScript(captureID: String? = nil) throws -> (URL, String) {
    let id = captureID ?? UUID().uuidString
    // Use single-quoted %s to avoid \n being interpreted as newline in shell
    let script = """
    #!/bin/sh
    output_base=""
    prompt_val=""
    capturing=""
    for i in "$@"; do
      if [ "$capturing" = "yes" ]; then
        prompt_val="$i"
        capturing=""
      fi
      if [ "$i" = "--prompt" ]; then
        capturing="yes"
      fi
      if [ "$1" = "-of" ]; then shift; output_base="$1"; fi
      shift
    done
    printf '%s\n' "$prompt_val" > /tmp/captured_prompt_\(id).txt
    while [ "$#" -gt 0 ]; do
      if [ "$1" = "-of" ]; then shift; output_base="$1"; fi
      shift
    done
    printf 'ok\n' > "${output_base}.txt"
    exit 0
    """
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("fake-whisper-\(id).sh")
    try script.write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: Int16(0o755))], ofItemAtPath: url.path)
    return (url, id)
}
