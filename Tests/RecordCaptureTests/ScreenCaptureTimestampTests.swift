import CoreMedia
import RecordCapture
import XCTest

final class ScreenCaptureTimestampTests: XCTestCase {
    func testTracksEachOutputClockIndependentlyWithoutRewritingPTS() throws {
        var tracker = ScreenCaptureTimestampTracker()
        let video = CMTime(value: 1_000, timescale: 600)
        let audio = CMTime(value: 47_900, timescale: 48_000)

        XCTAssertEqual(try tracker.observe(video, kind: .screen).time, video)
        XCTAssertEqual(try tracker.observe(audio, kind: .systemAudio).time, audio)
        XCTAssertNoThrow(
            try tracker.observe(CMTime(value: 1_001, timescale: 600), kind: .screen)
        )
    }

    func testRejectsRegressiveAndInvalidTimestamps() throws {
        var tracker = ScreenCaptureTimestampTracker()
        try tracker.observe(CMTime(value: 10, timescale: 10), kind: .microphone)

        XCTAssertThrowsError(
            try tracker.observe(CMTime(value: 9, timescale: 10), kind: .microphone)
        )
        XCTAssertThrowsError(try tracker.observe(.invalid, kind: .screen))
    }
}
