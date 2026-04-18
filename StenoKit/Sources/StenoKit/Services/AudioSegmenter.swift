import AVFoundation
import Foundation

public enum AudioSegmenterError: Error, LocalizedError {
    case failedToOpen(String)
    case unsupportedFormat
    case failedToWrite(String)

    public var errorDescription: String? {
        switch self {
        case .failedToOpen(let msg): return "Could not open audio file: \(msg)"
        case .unsupportedFormat: return "Audio format is not supported for segmentation."
        case .failedToWrite(let msg): return "Could not write segment: \(msg)"
        }
    }
}

/// Splits a recording into segments on silence gaps. This is the Swift-
/// side implementation of phrase-level segmentation for the segmented-
/// auto-detect flow: one whisper invocation per segment so each chunk
/// gets its own language decision, instead of whisper locking the whole
/// clip into a single detected language.
///
/// The algorithm is intentionally conservative:
///   1. Read PCM samples as Float32 mono (resampled/mixed if needed).
///   2. Compute RMS over non-overlapping windows (default 30ms).
///   3. Mark windows whose RMS is below `silenceThreshold` as silent.
///   4. Find runs of silence longer than `minSilenceDuration`.
///   5. Split at the midpoint of each silence run.
///   6. Drop segments shorter than `minSegmentDuration`.
///
/// When the input is short enough that no segmentation would help, or
/// when only one segment survives, the return is a single-element array
/// with the original URL — callers should treat that as the "don't
/// bother, transcribe the whole thing" fast path.
public struct AudioSegmenter: Sendable {
    public struct Configuration: Sendable {
        public var windowSeconds: Double
        public var minSilenceDuration: Double
        public var minSegmentDuration: Double
        public var silenceThreshold: Float
        public var maxSegments: Int

        public init(
            windowSeconds: Double = 0.030,
            minSilenceDuration: Double = 0.500,
            minSegmentDuration: Double = 0.500,
            silenceThreshold: Float = 0.015,
            maxSegments: Int = 8
        ) {
            self.windowSeconds = windowSeconds
            self.minSilenceDuration = minSilenceDuration
            self.minSegmentDuration = minSegmentDuration
            self.silenceThreshold = silenceThreshold
            self.maxSegments = maxSegments
        }
    }

    public struct SegmentSpan: Sendable, Equatable {
        public let startSeconds: Double
        public let endSeconds: Double
        public var duration: Double { endSeconds - startSeconds }
        public init(start: Double, end: Double) {
            self.startSeconds = start
            self.endSeconds = end
        }
    }

    public let config: Configuration
    public init(config: Configuration = Configuration()) {
        self.config = config
    }

    /// Pure-math segmentation: given a stream of per-window RMS values,
    /// returns the non-silent segments that should be transcribed
    /// separately. Split out so tests don't need real audio.
    public static func segmentSpans(
        rmsPerWindow: [Float],
        windowSeconds: Double,
        silenceThreshold: Float,
        minSilenceDuration: Double,
        minSegmentDuration: Double,
        maxSegments: Int
    ) -> [SegmentSpan] {
        guard !rmsPerWindow.isEmpty else { return [] }

        var spans: [SegmentSpan] = []
        var currentStart: Double?
        var silenceRunStart: Int?

        for i in 0..<rmsPerWindow.count {
            let isSilent = rmsPerWindow[i] < silenceThreshold
            let tNow = Double(i) * windowSeconds
            if !isSilent {
                if currentStart == nil {
                    currentStart = tNow
                }
                silenceRunStart = nil
            } else {
                if currentStart != nil, silenceRunStart == nil {
                    silenceRunStart = i
                }
                if let runStart = silenceRunStart {
                    let silenceLength = Double(i - runStart + 1) * windowSeconds
                    if silenceLength >= minSilenceDuration, let segStart = currentStart {
                        let splitMid = Double(runStart) * windowSeconds
                            + silenceLength / 2.0
                        spans.append(SegmentSpan(start: segStart, end: splitMid))
                        currentStart = nil
                        silenceRunStart = nil
                    }
                }
            }
        }
        // Flush trailing segment.
        if let segStart = currentStart {
            let endT = Double(rmsPerWindow.count) * windowSeconds
            spans.append(SegmentSpan(start: segStart, end: endT))
        }
        // Drop too-short and cap count.
        let filtered = spans.filter { $0.duration >= minSegmentDuration }
        if filtered.count <= maxSegments { return filtered }
        return Array(filtered.prefix(maxSegments))
    }

    /// Reads the audio at `url`, runs segmentation, and writes each
    /// segment out as a standalone WAV in `outputDirectory`. Returns the
    /// list of written segment URLs in chronological order. If only one
    /// span is found, returns `[url]` so callers can skip the re-write.
    public func splitAudio(
        at url: URL,
        outputDirectory: URL
    ) async throws -> [URL] {
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: url)
        } catch {
            throw AudioSegmenterError.failedToOpen(error.localizedDescription)
        }

        let sampleRate = file.processingFormat.sampleRate
        guard sampleRate > 0 else { throw AudioSegmenterError.unsupportedFormat }

        let totalFrames = AVAudioFrameCount(file.length)
        guard totalFrames > 0 else { return [url] }

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: totalFrames
        ) else {
            throw AudioSegmenterError.unsupportedFormat
        }
        try file.read(into: buffer, frameCount: totalFrames)

        let rms = Self.computeRMS(
            buffer: buffer,
            windowSeconds: config.windowSeconds,
            sampleRate: sampleRate
        )

        let spans = Self.segmentSpans(
            rmsPerWindow: rms,
            windowSeconds: config.windowSeconds,
            silenceThreshold: config.silenceThreshold,
            minSilenceDuration: config.minSilenceDuration,
            minSegmentDuration: config.minSegmentDuration,
            maxSegments: config.maxSegments
        )

        // If nothing to split into, bypass the write and let the caller
        // reuse the original URL.
        if spans.count <= 1 {
            return [url]
        }

        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )

        var outURLs: [URL] = []
        outURLs.reserveCapacity(spans.count)
        for (idx, span) in spans.enumerated() {
            let outURL = outputDirectory.appendingPathComponent(
                "segment-\(String(format: "%02d", idx))-\(UUID().uuidString).wav"
            )
            try Self.writeSegment(
                buffer: buffer,
                format: file.processingFormat,
                startSeconds: span.startSeconds,
                endSeconds: span.endSeconds,
                to: outURL
            )
            outURLs.append(outURL)
        }
        return outURLs
    }

    private static func computeRMS(
        buffer: AVAudioPCMBuffer,
        windowSeconds: Double,
        sampleRate: Double
    ) -> [Float] {
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return [] }
        let channelCount = Int(buffer.format.channelCount)
        let framesPerWindow = max(1, Int(windowSeconds * sampleRate))

        guard let channelData = buffer.floatChannelData else { return [] }
        var out: [Float] = []
        out.reserveCapacity(frameLength / framesPerWindow + 1)

        var frame = 0
        while frame < frameLength {
            let end = min(frame + framesPerWindow, frameLength)
            var sumSquares: Float = 0
            let count = end - frame
            for c in 0..<channelCount {
                let ch = channelData[c]
                for i in frame..<end {
                    let s = ch[i]
                    sumSquares += s * s
                }
            }
            let rms = sqrt(sumSquares / Float(max(1, count * channelCount)))
            out.append(rms)
            frame += framesPerWindow
        }
        return out
    }

    private static func writeSegment(
        buffer: AVAudioPCMBuffer,
        format: AVAudioFormat,
        startSeconds: Double,
        endSeconds: Double,
        to outURL: URL
    ) throws {
        let sampleRate = format.sampleRate
        let startFrame = max(0, AVAudioFrameCount(startSeconds * sampleRate))
        let endFrame = min(buffer.frameLength, AVAudioFrameCount(endSeconds * sampleRate))
        guard endFrame > startFrame else { return }
        let segmentFrames = endFrame - startFrame

        guard let segmentBuffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: segmentFrames
        ) else {
            throw AudioSegmenterError.unsupportedFormat
        }
        segmentBuffer.frameLength = segmentFrames

        let channelCount = Int(format.channelCount)
        guard let srcData = buffer.floatChannelData,
              let dstData = segmentBuffer.floatChannelData else {
            throw AudioSegmenterError.unsupportedFormat
        }
        for c in 0..<channelCount {
            for i in 0..<Int(segmentFrames) {
                dstData[c][i] = srcData[c][Int(startFrame) + i]
            }
        }

        let outFile: AVAudioFile
        do {
            outFile = try AVAudioFile(
                forWriting: outURL,
                settings: format.settings,
                commonFormat: format.commonFormat,
                interleaved: format.isInterleaved
            )
        } catch {
            throw AudioSegmenterError.failedToWrite(error.localizedDescription)
        }
        do {
            try outFile.write(from: segmentBuffer)
        } catch {
            throw AudioSegmenterError.failedToWrite(error.localizedDescription)
        }
    }
}
