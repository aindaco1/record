import CoreMedia
import RecordCapture
import RecordMedia
import XCTest

final class CommonMediaTimelineTests: XCTestCase {
    func testDelayedTracksMapToOneAnchorWithoutRewritingPresentationTime() throws {
        let anchor = CMTime(value: 600, timescale: 60)
        var timeline = try CommonMediaTimeline(anchor: anchor)
        let screenTime = CMTime(value: 601, timescale: 60)
        let delayedAudioTime = CMTime(value: 481_200, timescale: 48_000)

        let screen = try timeline.position(for: screenTime, kind: .screen)
        let audio = try timeline.position(for: delayedAudioTime, kind: .systemAudio)

        XCTAssertEqual(screen.presentationTime, screenTime)
        XCTAssertEqual(screen.timeSinceAnchor, CMTime(value: 1, timescale: 60))
        XCTAssertEqual(audio.presentationTime, delayedAudioTime)
        XCTAssertEqual(audio.timeSinceAnchor, CMTime(value: 1_200, timescale: 48_000))
    }

    func testGapsRemainVisibleAndClockJitterCannotMoveTrackBackward() throws {
        let anchor = CMTime(value: 100, timescale: 10)
        var timeline = try CommonMediaTimeline(anchor: anchor)
        _ = try timeline.position(for: CMTime(value: 101, timescale: 10), kind: .microphone)
        let afterGap = try timeline.position(
            for: CMTime(value: 150, timescale: 10),
            kind: .microphone
        )

        XCTAssertEqual(afterGap.timeSinceAnchor, CMTime(value: 50, timescale: 10))
        XCTAssertThrowsError(
            try timeline.position(for: CMTime(value: 149, timescale: 10), kind: .microphone)
        )
    }

    func testRejectsSamplesBeforeSharedAnchor() throws {
        var timeline = try CommonMediaTimeline(anchor: CMTime(value: 10, timescale: 1))

        XCTAssertThrowsError(
            try timeline.position(for: CMTime(value: 599, timescale: 60), kind: .screen)
        ) { error in
            XCTAssertEqual(
                error as? MediaTimelineError,
                .beforeAnchor(kind: .screen, presentationTime: CMTime(value: 599, timescale: 60))
            )
        }
    }

    func testRejectsSamplesFromAnotherClockEpoch() throws {
        let anchor = CMTime(value: 10, timescale: 1, flags: .valid, epoch: 2)
        var timeline = try CommonMediaTimeline(anchor: anchor)
        let otherClock = CMTime(value: 11, timescale: 1, flags: .valid, epoch: 3)

        XCTAssertThrowsError(
            try timeline.position(for: otherClock, kind: .systemAudio)
        ) { error in
            XCTAssertEqual(
                error as? MediaTimelineError,
                .clockEpochMismatch(kind: .systemAudio, expected: 2, actual: 3)
            )
        }
    }
}
