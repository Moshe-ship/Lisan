import Foundation

public enum WhisperCLITranscriptionError: Error, LocalizedError {
    case cliNotFound(path: String)
    case failedToRun(status: Int32, stderr: String)
    case outputMissing

    public var errorDescription: String? {
        switch self {
        case .cliNotFound(let path):
            return "whisper-cli not found at: \(path)"
        case .failedToRun(let status, let stderr):
            return "whisper-cli failed with status \(status): \(stderr)"
        case .outputMissing:
            return "whisper-cli completed but transcript output was missing"
        }
    }
}

public struct WhisperCLITranscriptionEngine: TranscriptionEngine, Sendable {
    public struct Configuration: Sendable {
        public var whisperCLIPath: URL
        public var modelPath: URL
        public var additionalArguments: [String]
        /// When true, auto-mode transcriptions run a `-dl` language
        /// detection preflight before the main decode. Costs one extra
        /// model-load but avoids whisper's mel-probe bias toward English
        /// on short Arabic clips (the common misfire for Gulf/Levantine
        /// speakers). Off by default — opt-in for accuracy over latency.
        public var twoPassAutoDetect: Bool

        public init(
            whisperCLIPath: URL,
            modelPath: URL,
            additionalArguments: [String] = [],
            twoPassAutoDetect: Bool = false
        ) {
            self.whisperCLIPath = whisperCLIPath
            self.modelPath = modelPath
            self.additionalArguments = additionalArguments
            self.twoPassAutoDetect = twoPassAutoDetect
        }
    }

    private let config: Configuration
    /// Cached at init to avoid copying ProcessInfo.environment + stat() calls per transcription.
    private let cachedEnvironment: [String: String]
    /// Vocabulary file loaded once at init. One phrase per line, used as a
    /// transcription prompt/hint to bias recognition toward custom terms.
    private let vocabularyText: String?

    public init(config: Configuration, vocabularyFileURL: URL? = nil) {
        self.config = config
        self.cachedEnvironment = Self.buildProcessEnvironment(config: config)
        self.vocabularyText = Self.loadVocabulary(at: vocabularyFileURL)
    }

    /// Loads vocabulary phrases from either a single text file or a directory.
    ///
    /// Accepting a directory lets users layer multiple "packs" (msa-business,
    /// khaleeji-common, saudi-places, gcc-brands, their own custom files) by
    /// pointing Lisan at a folder. All `.txt` files are read alphabetically,
    /// trimmed, de-duplicated, and joined with spaces.
    ///
    /// Comments starting with `#` are ignored.
    static func loadVocabulary(at url: URL?) -> String? {
        guard let url else { return nil }

        var files: [URL] = []
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else {
            return nil
        }

        if isDir.boolValue {
            let contents = (try? FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )) ?? []
            files = contents
                .filter { $0.pathExtension.lowercased() == "txt" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
        } else {
            files = [url]
        }

        var seen = Set<String>()
        var phrases: [String] = []
        for file in files {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            for rawLine in text.components(separatedBy: .newlines) {
                let line = rawLine.trimmingCharacters(in: .whitespaces)
                if line.isEmpty || line.hasPrefix("#") { continue }
                if seen.insert(line).inserted {
                    phrases.append(line)
                }
            }
        }

        return phrases.isEmpty ? nil : phrases.joined(separator: " ")
    }

    public func transcribe(audioURL: URL, languageHints: [String]) async throws -> RawTranscript {
        guard FileManager.default.fileExists(atPath: config.whisperCLIPath.path) else {
            throw WhisperCLITranscriptionError.cliNotFound(path: config.whisperCLIPath.path)
        }

        let outputBase = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("steno-out-\(UUID().uuidString)")

        let txtURL = outputBase.appendingPathExtension("txt")
        defer { try? FileManager.default.removeItem(at: txtURL) }

        var args: [String] = [
            "-m", config.modelPath.path,
            "-f", audioURL.path,
            "-of", outputBase.path,
            "-otxt",
            "-nt"
        ]

        // Determine language: explicit hint wins; auto mode passes `-l auto`
        // (whisper-cli's -l default is "en" so omitting the flag silently
        // forces English, not language detection).
        //
        // Two-pass path: when config opts in AND the hint resolves to auto,
        // run a `-dl` preflight to get a detected language code, then use
        // that as an explicit `-l` on the real decode. This trades one extra
        // model-load for materially better Arabic recognition on short
        // clips, where whisper's built-in single-pass auto-detect skews
        // English.
        let resolvedLang = await resolveLanguage(
            audioURL: audioURL,
            hint: languageHints.first
        )
        if let lang = resolvedLang {
            args.append(contentsOf: ["-l", lang])
        }

        // Vocabulary file: pass as --prompt to bias recognition toward custom terms
        if let vocab = vocabularyText, !vocab.isEmpty {
            args.append(contentsOf: ["--prompt", vocab])
        }

        args.append(contentsOf: config.additionalArguments)

        let result = try await ProcessRunner.run(
            executableURL: config.whisperCLIPath,
            arguments: args,
            environment: cachedEnvironment,
            standardOutput: FileHandle.nullDevice
        )

        let stderrText = String(data: result.standardError, encoding: .utf8) ?? ""

        guard result.terminationStatus == 0 else {
            throw WhisperCLITranscriptionError.failedToRun(status: result.terminationStatus, stderr: stderrText)
        }

        guard FileManager.default.fileExists(atPath: txtURL.path) else {
            throw WhisperCLITranscriptionError.outputMissing
        }

        let rawText = try String(contentsOf: txtURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let text = Self.stripArtifacts(rawText)

        return RawTranscript(text: text)
    }

    /// Returns the language code to pass to whisper-cli. If the hint resolves
    /// to a specific LanguageMode (en, ar, auto), honor it directly. For
    /// auto mode with two-pass enabled, run a -dl preflight and prefer the
    /// detected code; fall back to "auto" if the preflight fails or returns
    /// something we don't want to force (e.g. non-en/non-ar).
    private func resolveLanguage(audioURL: URL, hint: String?) async -> String? {
        guard let hint else { return nil }

        if let mode = LanguageMode(rawValue: hint.lowercased()),
           let langArg = mode.whisperLanguageArg {
            if mode == .auto, config.twoPassAutoDetect,
               let detected = await detectLanguage(audioURL: audioURL) {
                return detected
            }
            return langArg
        }

        if hint.lowercased() != "auto",
           let languageCode = normalizeLanguage(from: hint) {
            return languageCode
        }
        return nil
    }

    /// Runs `whisper-cli -dl` on the clip and parses the auto-detected
    /// language code from stderr. Returns nil if detection fails, if the
    /// detected language is not one we want to force (only en/ar pass
    /// through — other detections fall back to single-pass auto so we
    /// don't lock the decoder into Swedish because whisper's detector
    /// misfired on breath noise).
    private func detectLanguage(audioURL: URL) async -> String? {
        var args: [String] = [
            "-m", config.modelPath.path,
            "-f", audioURL.path,
            "-dl"
        ]
        args.append(contentsOf: config.additionalArguments)

        let result: ProcessExecutionResult
        do {
            result = try await ProcessRunner.run(
                executableURL: config.whisperCLIPath,
                arguments: args,
                environment: cachedEnvironment,
                standardOutput: FileHandle.nullDevice
            )
        } catch {
            return nil
        }
        guard result.terminationStatus == 0 else { return nil }

        let stderrText = String(data: result.standardError, encoding: .utf8) ?? ""
        // whisper.cpp prints: "auto-detected language: <code> (p = <float>)"
        let marker = "auto-detected language: "
        guard let markerRange = stderrText.range(of: marker) else { return nil }
        let tail = stderrText[markerRange.upperBound...]
        let code = tail.prefix { $0.isLetter || $0 == "-" }
        let normalized = String(code).lowercased()
        guard !normalized.isEmpty else { return nil }

        // Allow-list: we only force the decoder into languages we
        // actually support. A Swedish detection is almost always a
        // misfire on noise, so fall back to plain -l auto which is
        // more resilient in practice.
        return (normalized == "en" || normalized == "ar") ? normalized : "auto"
    }

    private func normalizeLanguage(from hint: String) -> String? {
        let lower = hint.lowercased()
        if lower == "en-us" || lower == "en" || lower == "english" {
            return "en"
        }
        if lower == "ar" || lower == "ar-eg" || lower == "arabic" {
            return "ar"
        }
        if lower.contains("-") {
            return String(lower.split(separator: "-").first ?? "")
        }
        return lower.isEmpty ? nil : lower
    }

    private static func buildProcessEnvironment(config: Configuration) -> [String: String] {
        WhisperRuntimeConfiguration.processEnvironment(
            whisperCLIPath: config.whisperCLIPath.path,
            modelPath: config.modelPath.path
        )
    }

    // MARK: - Artifact Stripping

    private static let artifactSet: Set<String> = [
        "music", "applause", "laughter", "noise", "silence", "inaudible",
        "background noise", "blank_audio", "blank audio", "audio is blank",
        "buzzing", "crowd", "cheering", "clapping", "sound effects"
    ]

    private static let bracketPattern = try! NSRegularExpression(pattern: #"\[([^\]]{1,40})\]"#)
    private static let parenPattern = try! NSRegularExpression(pattern: #"\(([^)]{1,40})\)"#)
    private static let multiSpacePattern = try! NSRegularExpression(pattern: #" {2,}"#)

    static func stripArtifacts(_ text: String) -> String {
        var result = text
        let fullRange = NSRange(result.startIndex..., in: result)

        // Remove bracketed artifacts like [Music], [BLANK_AUDIO]
        for match in bracketPattern.matches(in: result, range: fullRange).reversed() {
            guard let innerRange = Range(match.range(at: 1), in: result) else { continue }
            let inner = result[innerRange].trimmingCharacters(in: .whitespaces).lowercased()
            if artifactSet.contains(inner) {
                let outerRange = Range(match.range, in: result)!
                result.removeSubrange(outerRange)
            }
        }

        // Remove parenthetical artifacts like (buzzing), (Music)
        let updatedRange = NSRange(result.startIndex..., in: result)
        for match in parenPattern.matches(in: result, range: updatedRange).reversed() {
            guard let innerRange = Range(match.range(at: 1), in: result) else { continue }
            let inner = result[innerRange].trimmingCharacters(in: .whitespaces).lowercased()
            if artifactSet.contains(inner) {
                let outerRange = Range(match.range, in: result)!
                result.removeSubrange(outerRange)
            }
        }

        // Collapse multiple spaces and trim
        let collapsedRange = NSRange(result.startIndex..., in: result)
        result = multiSpacePattern.stringByReplacingMatches(in: result, range: collapsedRange, withTemplate: " ")
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
