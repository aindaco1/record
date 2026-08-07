import CoreMedia
import RecordCapture
import RecordMedia
import XCTest

final class IndependentMediaTimelineTests: XCTestCase {
    func testFirstSamplesMayArriveOutOfTimestampOrder() throws {
        var timeline = IndependentMediaTimeline()

        let system = try timeline.observe(
            CMTime(value: 489_600, timescale: 48_000),
            kind: .systemAudio
        )
        let microphone = try timeline.observe(
            CMTime(value: 484_800, timescale: 48_000),
            kind: .microphone
        )
        let screen = try timeline.observe(
            CMTime(value: 600, timescale: 60),
            kind: .screen
        )

        XCTAssertEqual(system.trackAnchor, system.presentationTime)
        XCTAssertEqual(microphone.trackAnchor, microphone.presentationTime)
        XCTAssertEqual(screen.trackAnchor, screen.presentationTime)
        XCTAssertEqual(
            timeline.startOffsetMilliseconds,
            [.screen: 0, .microphone: 100, .systemAudio: 200]
        )
    }

    func testGapsRemainVisibleAndTrackCannotMoveBackward() throws {
        var timeline = IndependentMediaTimeline()
        _ = try timeline.observe(CMTime(value: 100, timescale: 10), kind: .microphone)
        let afterGap = try timeline.observe(
            CMTime(value: 150, timescale: 10),
            kind: .microphone
        )

        XCTAssertEqual(afterGap.timeSinceTrackAnchor, CMTime(value: 50, timescale: 10))
        XCTAssertThrowsError(
            try timeline.observe(CMTime(value: 149, timescale: 10), kind: .microphone)
        ) { error in
            XCTAssertEqual(
                error as? MediaTimelineError,
                .nonMonotonic(
                    kind: .microphone,
                    previous: CMTime(value: 150, timescale: 10),
                    current: CMTime(value: 149, timescale: 10)
                )
            )
        }
    }

    func testRejectsSamplesFromAnotherClockEpoch() throws {
        var timeline = IndependentMediaTimeline()
        _ = try timeline.observe(
            CMTime(value: 10, timescale: 1, flags: .valid, epoch: 2),
            kind: .screen
        )
        let otherClock = CMTime(value: 11, timescale: 1, flags: .valid, epoch: 3)

        XCTAssertThrowsError(
            try timeline.observe(otherClock, kind: .systemAudio)
        ) { error in
            XCTAssertEqual(
                error as? MediaTimelineError,
                .clockEpochMismatch(kind: .systemAudio, expected: 2, actual: 3)
            )
        }
    }
}
