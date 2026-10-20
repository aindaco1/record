import AppKit
@testable import Record
import XCTest

@MainActor
final class ZoomApplicationMonitorTests: XCTestCase {
    func testInitialSnapshotLaunchQuitAndStopWithoutOpeningApps() {
        let center = NotificationCenter()
        let state = Snapshot()
        let monitor = ZoomApplicationMonitor(notificationCenter: center, running: { state.running })
        state.running = true
        monitor.start { state.observed.append($0) }
        XCTAssertEqual(state.observed, [true])
        state.running = false
        center.post(name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        XCTAssertEqual(state.observed, [true, false])
        state.running = true
        center.post(name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        XCTAssertEqual(state.observed, [true, false, true])
        monitor.stop()
        state.running = false
        center.post(name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        XCTAssertEqual(state.observed, [true, false, true])
    }

    func testRestartingMonitorDoesNotAccumulateObservers() {
        let center = NotificationCenter()
        let state = Snapshot()
        let monitor = ZoomApplicationMonitor(notificationCenter: center, running: { state.running })
        for _ in 0..<2 { monitor.start { state.observed.append($0) } }
        state.observed.removeAll()
        state.running = true
        center.post(name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        XCTAssertEqual(state.observed, [true])
    }
}

// All access occurs synchronously on the main queue, including notifications.
private final class Snapshot: @unchecked Sendable {
    var running = false
    var observed: [Bool] = []
}
