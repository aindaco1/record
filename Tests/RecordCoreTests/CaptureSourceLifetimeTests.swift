import RecordCore
import XCTest

final class CaptureSourceLifetimeTests: XCTestCase {
    func testSelectedApplicationExitFailsOnceWithoutPrivateMetadata() {
        var lifetime = CaptureSourceLifetime(processIDs: [42])
        XCTAssertNil(lifetime.applicationTerminated(processID: 7))
        XCTAssertEqual(
            lifetime.applicationTerminated(processID: 42),
            CaptureFailure(
                code: .sourceUnavailable,
                summary: "the selected capture source is no longer available"
            )
        )
        XCTAssertNil(lifetime.applicationTerminated(processID: 42))
    }

    func testMultiProcessSourceRemainsAvailableUntilLastProcessExits() {
        var lifetime = CaptureSourceLifetime(processIDs: [42, 43])
        XCTAssertNil(lifetime.applicationTerminated(processID: 42))
        XCTAssertNil(lifetime.applicationTerminated(processID: 42))
        XCTAssertEqual(lifetime.applicationTerminated(processID: 43)?.code, .sourceUnavailable)
    }

    func testDisplayAndRegionDoNotDependOnApplicationLifetimes() {
        var lifetime = CaptureSourceLifetime(processIDs: [])
        XCTAssertNil(lifetime.applicationTerminated(processID: 42))
    }

    func testIntentionalStopIgnoresLaterApplicationExit() {
        var lifetime = CaptureSourceLifetime(processIDs: [42])
        lifetime.cancel()
        XCTAssertNil(lifetime.applicationTerminated(processID: 42))
    }
}
