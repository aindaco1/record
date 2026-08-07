import Foundation
@testable import Record
import XCTest

final class RecordingElapsedClockTests: XCTestCase {
    func testExcludesPausedTimeAndIsIdempotent() {
        let start = Date(timeIntervalSince1970: 100)
        var clock = RecordingElapsedClock()

        clock.start(at: start)
        clock.pause(at: start.addingTimeInterval(3))
        clock.pause(at: start.addingTimeInterval(8))
        XCTAssertEqual(clock.elapsed(at: start.addingTimeInterval(8)), 3)
        XCTAssertTrue(clock.isPaused)

        clock.resume(at: start.addingTimeInterval(10))
        clock.resume(at: start.addingTimeInterval(11))
        XCTAssertEqual(clock.stop(at: start.addingTimeInterval(15)), 8)
        XCTAssertEqual(clock.elapsed(at: start.addingTimeInterval(20)), 8)
    }

    func testNeverAccumulatesNegativeTime() {
        let start = Date(timeIntervalSince1970: 100)
        var clock = RecordingElapsedClock()

        clock.start(at: start)
        clock.pause(at: start.addingTimeInterval(-1))

        XCTAssertEqual(clock.captured, 0)
    }
}
