import Foundation
import Testing
@testable import StenoKit

/// These tests cover the pure-math half of AudioSegmenter — the RMS →
/// span resolver — so we don't need real audio files in the test suite.
/// The I/O half is exercised during integration runs against real
/// recordings.

@Test("Single continuous speech: one span covers the whole clip")
func segmenterSingleSpan() {
    let rms: [Float] = Array(repeating: 0.1, count: 100) // 3 seconds at 30ms windows
    let spans = AudioSegmenter.segmentSpans(
        rmsPerWindow: rms,
        windowSeconds: 0.030,
        silenceThreshold: 0.015,
        minSilenceDuration: 0.500,
        minSegmentDuration: 0.500,
        maxSegments: 8
    )
    #expect(spans.count == 1)
    #expect(spans[0].startSeconds == 0)
    #expect(abs(spans[0].endSeconds - 3.0) < 0.05)
}

@Test("One long silence gap in the middle splits into two spans")
func segmenterOneGapSplits() {
    // 30 windows speech, 20 windows silence (600ms), 30 windows speech
    var rms: [Float] = Array(repeating: 0.1, count: 30)
    rms.append(contentsOf: Array(repeating: 0.001, count: 20))
    rms.append(contentsOf: Array(repeating: 0.1, count: 30))

    let spans = AudioSegmenter.segmentSpans(
        rmsPerWindow: rms,
        windowSeconds: 0.030,
        silenceThreshold: 0.015,
        minSilenceDuration: 0.500,
        minSegmentDuration: 0.300,
        maxSegments: 8
    )
    #expect(spans.count == 2, "Expected 2 spans, got \(spans.count)")
    #expect(spans[0].startSeconds == 0)
    #expect(spans[0].endSeconds > 0.75)
    #expect(spans[1].startSeconds > 0.9)
}

@Test("Silence shorter than threshold does not split")
func segmenterShortSilenceIgnored() {
    // 30 windows speech, 10 windows silence (300ms < 500ms threshold),
    // 30 windows speech. Should remain one span.
    var rms: [Float] = Array(repeating: 0.1, count: 30)
    rms.append(contentsOf: Array(repeating: 0.001, count: 10))
    rms.append(contentsOf: Array(repeating: 0.1, count: 30))

    let spans = AudioSegmenter.segmentSpans(
        rmsPerWindow: rms,
        windowSeconds: 0.030,
        silenceThreshold: 0.015,
        minSilenceDuration: 0.500,
        minSegmentDuration: 0.300,
        maxSegments: 8
    )
    #expect(spans.count == 1, "Expected 1 span (short gap shouldn't split), got \(spans.count)")
}

@Test("Spans shorter than minSegmentDuration are filtered out")
func segmenterDropsTooShortSpans() {
    // 3 windows speech (90ms), 20 windows silence, 30 windows speech.
    // First span (90ms + half of silence ≈ 390ms) is shorter than 500ms
    // minimum, so only the long second span survives the filter.
    var rms: [Float] = Array(repeating: 0.1, count: 3)
    rms.append(contentsOf: Array(repeating: 0.001, count: 20))
    rms.append(contentsOf: Array(repeating: 0.1, count: 30))

    let spans = AudioSegmenter.segmentSpans(
        rmsPerWindow: rms,
        windowSeconds: 0.030,
        silenceThreshold: 0.015,
        minSilenceDuration: 0.500,
        minSegmentDuration: 0.500,
        maxSegments: 8
    )
    #expect(spans.count == 1)
    #expect(spans[0].duration >= 0.5)
}

@Test("maxSegments caps the returned span count")
func segmenterMaxCap() {
    // Build 10 speech/silence cycles.
    var rms: [Float] = []
    for _ in 0..<10 {
        rms.append(contentsOf: Array(repeating: 0.1, count: 30))
        rms.append(contentsOf: Array(repeating: 0.001, count: 20))
    }
    let spans = AudioSegmenter.segmentSpans(
        rmsPerWindow: rms,
        windowSeconds: 0.030,
        silenceThreshold: 0.015,
        minSilenceDuration: 0.500,
        minSegmentDuration: 0.300,
        maxSegments: 3
    )
    #expect(spans.count <= 3)
}

@Test("Empty RMS stream returns empty spans")
func segmenterEmptyStream() {
    let spans = AudioSegmenter.segmentSpans(
        rmsPerWindow: [],
        windowSeconds: 0.030,
        silenceThreshold: 0.015,
        minSilenceDuration: 0.500,
        minSegmentDuration: 0.500,
        maxSegments: 8
    )
    #expect(spans.isEmpty)
}
