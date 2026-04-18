import Foundation

public enum WhisperModelDownloadError: Error, LocalizedError {
    case networkFailure(String)
    case httpFailure(Int)
    case sizeMismatch(expected: Int64, actual: Int64)
    case writeFailure(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .networkFailure(let detail):
            return "Network error: \(detail)"
        case .httpFailure(let code):
            return "Download failed with HTTP \(code)"
        case .sizeMismatch(let expected, let actual):
            return "Downloaded file is \(actual) bytes, expected \(expected). File looks corrupted — try again."
        case .writeFailure(let detail):
            return "Could not save model: \(detail)"
        case .cancelled:
            return "Download cancelled."
        }
    }
}

/// Downloads whisper models from the catalog with progress callbacks.
/// Streams to a temp file then atomically moves to the target location,
/// so an interrupted download never leaves a half-file at the real path.
public actor WhisperModelDownloader {
    public struct Progress: Sendable {
        public let bytesDownloaded: Int64
        public let totalBytes: Int64
        public var fraction: Double {
            guard totalBytes > 0 else { return 0 }
            return Double(bytesDownloaded) / Double(totalBytes)
        }
    }

    private let urlSession: URLSession
    private var activeTask: URLSessionDownloadTask?

    public init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    public func cancel() {
        activeTask?.cancel()
        activeTask = nil
    }

    /// Downloads the model described by `entry` into `directory`. Returns
    /// the final on-disk URL of the installed model. Progress is reported
    /// via the supplied closure on an unspecified queue — marshal to the
    /// main actor yourself if updating UI.
    public func download(
        entry: WhisperModelCatalog.Entry,
        into directory: URL,
        progress: @escaping @Sendable (Progress) -> Void
    ) async throws -> URL {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let destination = directory.appendingPathComponent(entry.filename)

        return try await withCheckedThrowingContinuation { continuation in
            let delegate = DownloadDelegate(
                expectedSize: entry.expectedSizeBytes,
                destination: destination,
                progressCallback: progress,
                completion: { result in
                    continuation.resume(with: result)
                }
            )
            let session = URLSession(
                configuration: urlSession.configuration,
                delegate: delegate,
                delegateQueue: nil
            )
            let task = session.downloadTask(with: entry.downloadURL)
            self.activeTask = task
            task.resume()
        }
    }
}

private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let expectedSize: Int64
    private let destination: URL
    private let progressCallback: @Sendable (WhisperModelDownloader.Progress) -> Void
    private let completion: (Result<URL, Error>) -> Void
    private var completed = false

    init(
        expectedSize: Int64,
        destination: URL,
        progressCallback: @escaping @Sendable (WhisperModelDownloader.Progress) -> Void,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        self.expectedSize = expectedSize
        self.destination = destination
        self.progressCallback = progressCallback
        self.completion = completion
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : expectedSize
        progressCallback(.init(bytesDownloaded: totalBytesWritten, totalBytes: total))
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard !completed else { return }

        if let response = downloadTask.response as? HTTPURLResponse,
           !(200..<300).contains(response.statusCode) {
            completed = true
            completion(.failure(WhisperModelDownloadError.httpFailure(response.statusCode)))
            return
        }

        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: location.path)
            if let size = attrs[.size] as? NSNumber {
                let actual = size.int64Value
                let minimum = Int64(Double(expectedSize) * 0.95)
                if actual < minimum {
                    completed = true
                    completion(.failure(
                        WhisperModelDownloadError.sizeMismatch(expected: expectedSize, actual: actual)
                    ))
                    return
                }
            }

            // Atomic move into the target directory. If an older file
            // exists, replace it in place so paths already configured
            // in preferences continue to resolve.
            if FileManager.default.fileExists(atPath: destination.path) {
                _ = try? FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: location, to: destination)
            completed = true
            completion(.success(destination))
        } catch {
            completed = true
            completion(.failure(WhisperModelDownloadError.writeFailure(error.localizedDescription)))
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard !completed, let error else { return }
        completed = true
        let nsError = error as NSError
        if nsError.code == NSURLErrorCancelled {
            completion(.failure(WhisperModelDownloadError.cancelled))
        } else {
            completion(.failure(WhisperModelDownloadError.networkFailure(error.localizedDescription)))
        }
    }
}
