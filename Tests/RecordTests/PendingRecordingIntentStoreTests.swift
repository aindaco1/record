@testable import Record
import XCTest

@MainActor
final class PendingRecordingIntentStoreTests: XCTestCase {
    func testFlowArmsBeforeRequestAndSecondClickRestarts() {
        var flow = RecordingPermissionFlowState()

        XCTAssertEqual(
            flow.begin(.screen, resumingAfterRestart: false),
            .request
        )
        XCTAssertEqual(flow.pendingMode, .screen)
        XCTAssertEqual(
            flow.begin(.screen, resumingAfterRestart: false),
            .restart
        )
        XCTAssertEqual(flow.pendingMode, .screen)
    }

    func testResumedFlowRequestsOnceInsteadOfRestartLooping() {
        var flow = RecordingPermissionFlowState()
        flow.arm(.audioOnly)

        XCTAssertEqual(
            flow.begin(.audioOnly, resumingAfterRestart: true),
            .request
        )
        flow.clear()
        XCTAssertNil(flow.pendingMode)
    }

    func testIntentIsConsumedExactlyOnce() throws {
        let defaults = try makeDefaults()
        let store = PendingRecordingIntentStore(defaults: defaults)

        store.save(.screen)

        XCTAssertEqual(store.consume(), .screen)
        XCTAssertNil(store.consume())
    }

    func testAudioOnlyIntentRoundTripsAndClearRemovesIt() throws {
        let defaults = try makeDefaults()
        let store = PendingRecordingIntentStore(defaults: defaults)

        store.save(.audioOnly)
        store.clear()

        XCTAssertNil(store.consume())
    }

    func testInvalidIntentFailsClosedAndIsRemoved() throws {
        let defaults = try makeDefaults()
        defaults.set("remote-stream", forKey: PendingRecordingIntentStore.key)
        let store = PendingRecordingIntentStore(defaults: defaults)

        XCTAssertNil(store.consume())
        XCTAssertNil(defaults.object(forKey: PendingRecordingIntentStore.key))
    }

    private func makeDefaults() throws -> UserDefaults {
        let suite = "com.aindaco.record.pending-intent-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suite)
        }
        return defaults
    }
}
