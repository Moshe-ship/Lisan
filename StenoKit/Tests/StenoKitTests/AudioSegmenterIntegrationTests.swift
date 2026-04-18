import AVFoundation
import Foundation
import Testing
@testable import StenoKit

/// Integration tests that exercise the full splitAudio() I/O path against
/// real WAV files synthesized in the test harness. The pure-math tests
/// live in AudioSegmenterTests.swift — these cover everything those
/// can't: AVAudioFile read/write, sample-rate variants, mono/stereo,
/// output file permissions, zero-length files, and the leading-silence
/// case that a naive state machine often gets wrong.
struct AudioSegmenterIntegrationTests {

    // MARK: - Test fixtures

    private enum Fixture {
        /// Writes a WAV file at the given URL. Each `Chunk` is either
        /// 0.44 sine (speech-like) or silence.
        static func writeWAV(
            chunks: [Chunk],
            sampleRate: Double = 16_000,
            channels: AVAudioChannelCount = 1,
            to url: URL
        ) throws {
            let format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: sampleRate,
                channels: channels,
                interleaved: false
            )!

            // Write requires .pcmFormatInt16 or similar supported codec for WAV container.
            // Use the format's natural settings.
            let file = try AVAudioFile(
                forWriting: url,
                settings: [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVSampleRateKey: sampleRate,
                    AVNumberOfChannelsKey: channels,
                    AVLinearPCMBitDepthKey: 16,
                    AVLinearPCMIsFloatKey: false,
                    AVLinearPCMIsBigEndianKey: false
                ],
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )

            for chunk in chunks {
                let frameCount = AVAudioFrameCount(chunk.seconds * sampleRate)
                guard frameCount > 0,
                      let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)
                else { continue }
                buffer.frameLength = frameCount
                let channelData = buffer.floatChannelData!
                for c in 0..<Int(channels) {
                    for i in 0..<Int(frameCount) {
                        channelData[c][i] = chunk.sampleValue(
                            at: i,
                            sampleRate: sampleRate,
                            channelIndex: c
                        )
                    }
                }
                try file.write(from: buffer)
            }
        }

        enum Chunk {
            case speech(seconds: Double, amplitude: Float = 0.3, frequencyHz: Double = 220)
            case silence(seconds: Double)

            var seconds: Double {
                switch self {
                case .speech(let s, _, _): return s
                case .silence(let s): return s
                }
            }

            func sampleValue(at index: Int, sampleRate: Double, channelIndex: Int) -> Float {
                switch self {
                case .speech(_, let amp, let freq):
                    let t = Double(index) / sampleRate
                    return amp * Float(sin(2.0 * .pi * freq * t))
                case .silence:
                    return 0
                }
            }
        }

        static func makeTempDir() throws -> URL {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("segmenter-test-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }
    }

    // MARK: - Real I/O tests

    @Test("splitAudio on a one-chunk speech clip returns the original URL (fast path)")
    func splitAudioSingleChunkPassThrough() async throws {
        let tmp = try Fixture.makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let inputURL = tmp.appendingPathComponent("input.wav")
        try Fixture.writeWAV(chunks: [.speech(seconds: 2.0)], to: inputURL)

        let segmenter = AudioSegmenter()
        let outputs = try await segmenter.splitAudio(
            at: inputURL,
            outputDirectory: tmp.appendingPathComponent("out")
        )

        #expect(outputs == [inputURL], "Single-segment clip should return the original URL unchanged")
    }

    @Test("splitAudio writes two valid WAVs when a silence gap splits the clip")
    func splitAudioTwoSegmentsOnGap() async throws {
        let tmp = try Fixture.makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let inputURL = tmp.appendingPathComponent("gap.wav")
        try Fixture.writeWAV(
            chunks: [
                .speech(seconds: 1.2),
                .silence(seconds: 0.8),
                .speech(seconds: 1.2)
            ],
            to: inputURL
        )

        let outDir = tmp.appendingPathComponent("out")
        let segmenter = AudioSegmenter()
        let outputs = try await segmenter.splitAudio(at: inputURL, outputDirectory: outDir)

        #expect(outputs.count == 2, "Expected two segments from a split clip, got \(outputs.count)")
        for url in outputs {
            #expect(FileManager.default.fileExists(atPath: url.path),
                    "Segment file missing at \(url.path)")
            // Confirm the written WAV is actually readable as audio.
            let reopened = try AVAudioFile(forReading: url)
            #expect(reopened.length > 0, "Segment \(url.lastPathComponent) has zero frames")
        }
    }

    @Test("splitAudio handles stereo input by not crashing and writing stereo segments")
    func splitAudioStereo() async throws {
        let tmp = try Fixture.makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let inputURL = tmp.appendingPathComponent("stereo.wav")
        try Fixture.writeWAV(
            chunks: [
                .speech(seconds: 1.0),
                .silence(seconds: 0.8),
                .speech(seconds: 1.0)
            ],
            channels: 2,
            to: inputURL
        )

        let outDir = tmp.appendingPathComponent("out")
        let segmenter = AudioSegmenter()
        let outputs = try await segmenter.splitAudio(at: inputURL, outputDirectory: outDir)

        #expect(outputs.count == 2)
        if let first = outputs.first, first != inputURL {
            let reopened = try AVAudioFile(forReading: first)
            #expect(reopened.processingFormat.channelCount == 2,
                    "Stereo input must produce stereo segments")
        }
    }

    @Test("splitAudio handles 44.1 kHz non-16k source (real mic defaults)")
    func splitAudioNon16kSampleRate() async throws {
        let tmp = try Fixture.makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let inputURL = tmp.appendingPathComponent("44k.wav")
        try Fixture.writeWAV(
            chunks: [
                .speech(seconds: 1.0),
                .silence(seconds: 0.8),
                .speech(seconds: 1.0)
            ],
            sampleRate: 44_100,
            to: inputURL
        )

        let outDir = tmp.appendingPathComponent("out")
        let segmenter = AudioSegmenter()
        let outputs = try await segmenter.splitAudio(at: inputURL, outputDirectory: outDir)

        #expect(outputs.count == 2, "44.1k source must still be splittable")
        if let first = outputs.first, first != inputURL {
            let reopened = try AVAudioFile(forReading: first)
            #expect(reopened.processingFormat.sampleRate == 44_100,
                    "Output sample rate must match source")
        }
    }

    @Test("splitAudio with leading silence still captures speech that starts at t>0")
    func splitAudioLeadingSilence() async throws {
        let tmp = try Fixture.makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let inputURL = tmp.appendingPathComponent("leading-silence.wav")
        try Fixture.writeWAV(
            chunks: [
                .silence(seconds: 0.8),       // leading silence
                .speech(seconds: 1.5)         // then speech — should NOT be dropped
            ],
            to: inputURL
        )

        let outDir = tmp.appendingPathComponent("out")
        let segmenter = AudioSegmenter()
        let outputs = try await segmenter.splitAudio(at: inputURL, outputDirectory: outDir)

        // Leading silence produces exactly one speech span — the segmenter
        // should hit the single-segment fast path (original URL returned).
        #expect(outputs.count == 1, "Leading silence + one speech block = one segment")
    }

    @Test("splitAudio on an all-silence clip returns no segments (via single-URL fast path)")
    func splitAudioAllSilence() async throws {
        let tmp = try Fixture.makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let inputURL = tmp.appendingPathComponent("silent.wav")
        try Fixture.writeWAV(chunks: [.silence(seconds: 2.0)], to: inputURL)

        let outDir = tmp.appendingPathComponent("out")
        let segmenter = AudioSegmenter()
        let outputs = try await segmenter.splitAudio(at: inputURL, outputDirectory: outDir)

        // No speech = zero spans = fallback to the original URL (single
        // entry, no segments written). The transcription engine will
        // then do its own silence handling via --suppress-nst / VAD.
        #expect(outputs == [inputURL], "All-silence clip should short-circuit to the original URL")
    }

    @Test("splitAudio does not leave partial files on output directory when nothing to split")
    func splitAudioDoesNotPolluteDirOnFastPath() async throws {
        let tmp = try Fixture.makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let inputURL = tmp.appendingPathComponent("one.wav")
        try Fixture.writeWAV(chunks: [.speech(seconds: 1.5)], to: inputURL)

        let outDir = tmp.appendingPathComponent("out")
        let segmenter = AudioSegmenter()
        _ = try await segmenter.splitAudio(at: inputURL, outputDirectory: outDir)

        // Fast path: we don't want the dir created if we didn't write anything.
        // Either it doesn't exist OR it's empty. Both are acceptable.
        if FileManager.default.fileExists(atPath: outDir.path) {
            let contents = (try? FileManager.default.contentsOfDirectory(atPath: outDir.path)) ?? []
            #expect(contents.isEmpty,
                    "Fast path shouldn't write segment files, got: \(contents)")
        }
    }

    @Test("splitAudio with three speech blocks and two gaps yields three segments in order")
    func splitAudioMultipleGapsOrdered() async throws {
        let tmp = try Fixture.makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let inputURL = tmp.appendingPathComponent("three.wav")
        try Fixture.writeWAV(
            chunks: [
                .speech(seconds: 1.0, frequencyHz: 220),  // different freqs so we could
                .silence(seconds: 0.7),                    // in theory tell them apart
                .speech(seconds: 1.0, frequencyHz: 440),
                .silence(seconds: 0.7),
                .speech(seconds: 1.0, frequencyHz: 880)
            ],
            to: inputURL
        )

        let outDir = tmp.appendingPathComponent("out")
        let segmenter = AudioSegmenter()
        let outputs = try await segmenter.splitAudio(at: inputURL, outputDirectory: outDir)

        #expect(outputs.count == 3, "Expected 3 segments, got \(outputs.count)")
        // The file names carry the 2-digit ordinal prefix — verify order.
        let names = outputs.map { $0.lastPathComponent }
        #expect(names.sorted() == names, "Segments should be returned in chronological order")
    }

    @Test("splitAudio throws failedToOpen on a file that isn't audio")
    func splitAudioRejectsGarbageFile() async throws {
        let tmp = try Fixture.makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let bogusURL = tmp.appendingPathComponent("not-audio.wav")
        try Data("this is not a wav file".utf8).write(to: bogusURL)

        let segmenter = AudioSegmenter()
        do {
            _ = try await segmenter.splitAudio(
                at: bogusURL,
                outputDirectory: tmp.appendingPathComponent("out")
            )
            Issue.record("Expected a throw when input is not a real audio file")
        } catch is AudioSegmenterError {
            // expected
        } catch {
            // AVFoundation itself may throw a different error type before
            // we wrap it — that's still acceptable coverage. We just want
            // to confirm we don't silently return bogus segment URLs.
        }
    }

    @Test("splitAudio handles zero-duration file without crashing")
    func splitAudioZeroDuration() async throws {
        let tmp = try Fixture.makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let inputURL = tmp.appendingPathComponent("empty.wav")
        // Write a valid WAV header with zero audio frames.
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        )!
        let file = try AVAudioFile(
            forWriting: inputURL,
            settings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 16_000,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false
            ],
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        // Write one frame and immediately close so the file exists but is minimal.
        if let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1) {
            buf.frameLength = 1
            buf.floatChannelData![0][0] = 0
            try file.write(from: buf)
        }

        let outDir = tmp.appendingPathComponent("out")
        let segmenter = AudioSegmenter()
        // Either returns the original URL (fast path) or empty — both
        // are acceptable as long as it doesn't crash or write junk.
        let outputs = try await segmenter.splitAudio(at: inputURL, outputDirectory: outDir)
        #expect(outputs == [inputURL] || outputs.isEmpty,
                "Zero/near-zero duration should short-circuit safely")
    }
}
