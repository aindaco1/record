import Foundation
import RecordCore
import XCTest

final class PluginLifecycleTests: XCTestCase {
    func testActivationFailureRestoresPreviouslyActivatedPlugins() async throws {
        let events = EventLog()
        let coordinator = PluginLifecycleCoordinator()
        let context = makeContext()
        let plugins: [any RecordingLifecyclePlugin] = [
            TestPlugin(id: "first", events: events),
            TestPlugin(id: "failing", events: events, shouldFail: true),
            TestPlugin(id: "never-reached", events: events),
        ]

        do {
            try await coordinator.activate(plugins, for: context)
            XCTFail("activation should fail")
        } catch let error as PluginLifecycleCoordinator.LifecycleError {
            guard case .activationFailed(let pluginID, _) = error else {
                return XCTFail("unexpected lifecycle error: \(error)")
            }
            XCTAssertEqual(pluginID, "failing")
        }

        let recordedEvents = await events.values()
        let finalState = await coordinator.state
        XCTAssertEqual(
            recordedEvents,
            ["activate:first", "activate:failing", "deactivate:first"]
        )
        XCTAssertEqual(finalState, .idle)
    }

    func testSuccessfulDeactivationRunsInReverseOrderAndIsIdempotent() async throws {
        let events = EventLog()
        let coordinator = PluginLifecycleCoordinator()
        let plugins: [any RecordingLifecyclePlugin] = [
            TestPlugin(id: "first", events: events),
            TestPlugin(id: "second", events: events),
        ]

        try await coordinator.activate(plugins, for: makeContext())
        await coordinator.deactivate()
        await coordinator.deactivate()

        let recordedEvents = await events.values()
        let finalState = await coordinator.state
        XCTAssertEqual(
            recordedEvents,
            [
                "activate:first",
                "activate:second",
                "deactivate:second",
                "deactivate:first",
            ]
        )
        XCTAssertEqual(finalState, .idle)
    }

    private func makeContext() -> RecordingPluginContext {
        RecordingPluginContext(
            sessionID: UUID(),
            sessionDirectory: URL(fileURLWithPath: "/tmp/record-test", isDirectory: true)
        )
    }
}

private actor EventLog {
    private var events: [String] = []

    func append(_ event: String) {
        events.append(event)
    }

    func values() -> [String] {
        events
    }
}

private struct TestPlugin: RecordingLifecyclePlugin {
    let id: String
    let events: EventLog
    var shouldFail = false

    func activate(for context: RecordingPluginContext) async throws {
        await events.append("activate:\(id)")
        if shouldFail {
            throw TestError.expected
        }
    }

    func deactivate(for context: RecordingPluginContext) async {
        await events.append("deactivate:\(id)")
    }

    enum TestError: Error {
        case expected
    }
}
