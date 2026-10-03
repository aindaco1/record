import RecordCore
import XCTest

final class RecordingAnnouncementPolicyTests: XCTestCase {
    func testClockAndMeterRefreshesStaySilentButPauseResumeAndStopAnnounce() {
        var policy = RecordingAnnouncementPolicy()
        XCTAssertNil(policy.transition(to: .idle))
        XCTAssertEqual(policy.transition(to: .recording), "Recording started")
        for _ in 0..<100 { XCTAssertNil(policy.transition(to: .recording)) }
        XCTAssertEqual(policy.transition(to: .paused), "Recording paused")
        XCTAssertNil(policy.transition(to: .paused))
        XCTAssertEqual(policy.transition(to: .recording), "Recording resumed")
        XCTAssertEqual(policy.transition(to: .idle), "Recording stopped")
        XCTAssertNil(policy.transition(to: .idle))
    }
}
