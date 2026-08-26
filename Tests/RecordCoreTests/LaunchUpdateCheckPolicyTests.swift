import RecordCore
import XCTest

final class LaunchUpdateCheckPolicyTests: XCTestCase {
    func testChecksOnceWhenUpdaterStartsWithAutomaticChecksEnabled() {
        XCTAssertTrue(
            LaunchUpdateCheckPolicy.shouldCheckInBackground(
                startingUpdater: true,
                automaticallyChecksForUpdates: true
            )
        )
    }

    func testSkipsCheckWhenUpdaterDoesNotStart() {
        XCTAssertFalse(
            LaunchUpdateCheckPolicy.shouldCheckInBackground(
                startingUpdater: false,
                automaticallyChecksForUpdates: true
            )
        )
    }

    func testSkipsCheckWhenAutomaticChecksAreDisabled() {
        XCTAssertFalse(
            LaunchUpdateCheckPolicy.shouldCheckInBackground(
                startingUpdater: true,
                automaticallyChecksForUpdates: false
            )
        )
    }
}
