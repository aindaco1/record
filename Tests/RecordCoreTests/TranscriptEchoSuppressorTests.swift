import RecordCore
import XCTest

final class TranscriptEchoSuppressorTests: XCTestCase {
    func testSuppressesAlignedMicCopiesAndKeepsLocalSpeech() {
        let segments: [TranscriptDocument.Segment] = [
            segment("me", 2_487, 2_807, "local test"),
            segment("them", 23_920, 26_080, "The lighthouse signal repeats every night."),
            segment("me", 24_007, 26_487, "The lighthouse signal repeats every night."),
            segment("them", 36_960, 38_880, "The green robot checks every sensor."),
            segment("me", 37_047, 38_967, "The green robot checked every sensor."),
            segment("me", 47_847, 50_727, "synthetic local speech remains here"),
        ]

        let result = TranscriptEchoSuppressor.suppress(segments)

        XCTAssertEqual(result.suppressedMicrophoneSegments.count, 2)
        XCTAssertEqual(
            result.segments.map(\.text),
            [
                "local test",
                "The lighthouse signal repeats every night.",
                "The green robot checks every sensor.",
                "synthetic local speech remains here",
            ]
        )
    }

    func testKeepsShortBackchannelsAndLateRepeatedSpeech() {
        let segments: [TranscriptDocument.Segment] = [
            segment("them", 1_000, 2_000, "Yeah"),
            segment("me", 1_100, 1_500, "Yeah"),
            segment("them", 4_000, 5_000, "Please review the report today"),
            segment("me", 7_000, 8_000, "Please review the report today"),
        ]

        let result = TranscriptEchoSuppressor.suppress(segments)

        XCTAssertTrue(result.suppressedMicrophoneSegments.isEmpty)
        XCTAssertEqual(result.segments, segments)
    }

    func testDifferentOverlappingSpeechIsNeverSuppressed() {
        let segments: [TranscriptDocument.Segment] = [
            segment("them", 1_000, 4_000, "I think we should ship it tomorrow"),
            segment("me", 1_100, 3_000, "No, I need another day please"),
        ]

        XCTAssertEqual(TranscriptEchoSuppressor.suppress(segments).segments, segments)
    }

    private func segment(
        _ speaker: String,
        _ start: Int,
        _ end: Int,
        _ text: String
    ) -> TranscriptDocument.Segment {
        .init(
            speaker: speaker,
            startMilliseconds: start,
            endMilliseconds: end,
            text: text
        )
    }
}
