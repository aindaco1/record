import AppKit
@testable import RecordCapture
import XCTest

final class ScreenCaptureSourceLifetimeMonitorTests: XCTestCase {
    @MainActor
    func testWorkspaceTerminationIsForwardedAsSourceUnavailable() async throws {
        let center = NotificationCenter()
        let application = NSRunningApplication.current
        let received = expectation(description: "selected application disappeared")
        let monitor = ScreenCaptureSourceLifetimeMonitor(
            processIDs: [application.processIdentifier],
            notificationCenter: center,
            applicationIsRunning: { _ in true },
            onFailure: { failure in
                XCTAssertEqual(failure.code, .sourceUnavailable)
                received.fulfill()
            }
        )
        try monitor.start()
        center.post(
            name: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            userInfo: [NSWorkspace.applicationUserInfoKey: application]
        )
        await fulfillment(of: [received], timeout: 1)
        monitor.stop()
    }

    @MainActor
    func testSourceThatExitedBeforeObserverRegistrationFailsStartup() {
        let monitor = ScreenCaptureSourceLifetimeMonitor(
            processIDs: [42],
            notificationCenter: NotificationCenter(),
            applicationIsRunning: { _ in false },
            onFailure: { _ in XCTFail("startup failure must be thrown to its owner") }
        )
        XCTAssertThrowsError(try monitor.start()) { error in
            guard case ScreenCaptureAdapterError.captureFailed(let failure) = error else {
                return XCTFail("expected classified capture failure")
            }
            XCTAssertEqual(failure.code, .sourceUnavailable)
        }
    }

    @MainActor
    func testObserverDoesNotRetainReleasedStreamMonitor() throws {
        let center = NotificationCenter()
        weak var releasedMonitor: ScreenCaptureSourceLifetimeMonitor?
        do {
            let monitor = ScreenCaptureSourceLifetimeMonitor(
                processIDs: [42],
                notificationCenter: center,
                applicationIsRunning: { _ in true },
                onFailure: { _ in XCTFail("released stream cannot report source loss") }
            )
            releasedMonitor = monitor
            try monitor.start()
        }
        XCTAssertNil(releasedMonitor)
    }
}
