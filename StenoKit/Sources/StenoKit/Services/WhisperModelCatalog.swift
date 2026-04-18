import Foundation

/// Catalog of whisper.cpp models we offer for download from inside the app.
/// Sourced from the canonical ggerganov/whisper.cpp Hugging Face release.
/// Limited to multilingual models since Lisan is bilingual by design —
/// English-only variants ("ggml-*.en.bin") are intentionally excluded.
public enum WhisperModelCatalog {
    public struct Entry: Sendable, Equatable, Identifiable {
        public let id: String
        public let displayName: String
        public let filename: String
        public let downloadURL: URL
        /// Canonical expected size in bytes — used as a post-download sanity
        /// check. If the file on disk doesn't match, the model is treated as
        /// corrupted/missing.
        public let expectedSizeBytes: Int64
        /// Human readable size, e.g. "148 MB".
        public let sizeLabel: String
        /// Short tagline for the picker row.
        public let summary: String

        public init(
            id: String,
            displayName: String,
            filename: String,
            downloadURL: URL,
            expectedSizeBytes: Int64,
            sizeLabel: String,
            summary: String
        ) {
            self.id = id
            self.displayName = displayName
            self.filename = filename
            self.downloadURL = downloadURL
            self.expectedSizeBytes = expectedSizeBytes
            self.sizeLabel = sizeLabel
            self.summary = summary
        }
    }

    public static let entries: [Entry] = [
        Entry(
            id: "tiny",
            displayName: "Tiny",
            filename: "ggml-tiny.bin",
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin")!,
            expectedSizeBytes: 77_691_713,
            sizeLabel: "74 MB",
            summary: "Fastest. English-biased; Arabic detection often wrong on short clips."
        ),
        Entry(
            id: "base",
            displayName: "Base",
            filename: "ggml-base.bin",
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin")!,
            expectedSizeBytes: 147_951_465,
            sizeLabel: "141 MB",
            summary: "Default. Fast, OK English, weak Arabic on short utterances."
        ),
        Entry(
            id: "small",
            displayName: "Small",
            filename: "ggml-small.bin",
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin")!,
            expectedSizeBytes: 487_601_967,
            sizeLabel: "465 MB",
            summary: "Recommended. Big accuracy jump for Arabic; still fast on Apple Silicon."
        ),
        Entry(
            id: "medium",
            displayName: "Medium",
            filename: "ggml-medium.bin",
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.bin")!,
            expectedSizeBytes: 1_533_763_059,
            sizeLabel: "1.5 GB",
            summary: "Most accurate practical option. Slower; use for careful work."
        )
    ]

    /// Resolves the catalog entry for a given on-disk model path by filename.
    /// Returns nil if the file isn't a model we ship in the catalog (e.g.
    /// user pointed to a custom path).
    public static func entry(forModelPath path: String) -> Entry? {
        let filename = (path as NSString).lastPathComponent
        return entries.first { $0.filename == filename }
    }

    /// Checks whether the model file exists at the given directory with
    /// a size that matches the expected bytes within a small tolerance.
    /// This catches interrupted downloads without needing a SHA pass.
    public static func isInstalled(
        entry: Entry,
        in directory: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        let path = directory.appendingPathComponent(entry.filename).path
        guard fileManager.fileExists(atPath: path),
              let attrs = try? fileManager.attributesOfItem(atPath: path),
              let size = attrs[.size] as? NSNumber else {
            return false
        }
        // Accept any file ≥ 95% of expected size. Partial downloads will
        // be well below this and get retried; small filesystem metadata
        // differences never account for 5%.
        let actual = size.int64Value
        return actual >= Int64(Double(entry.expectedSizeBytes) * 0.95)
    }
}
