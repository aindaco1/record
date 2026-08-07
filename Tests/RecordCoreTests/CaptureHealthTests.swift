import RecordCore
import XCTest

final class CaptureHealthTests: XCTestCase {
    func testRouteChangesDebounceAndRecoverThroughExplicitEffects() {
        var state = MicrophoneRouteRecoveryStateMachine()
        XCTAssertEqual(state.handle(.start), [])
        XCTAssertEqual(
            state.handle(.routeChanged(atMilliseconds: 1_000)),
            [.scheduleRestart(milliseconds: 500)]
        )
        XCTAssertEqual(
            state.handle(.routeChanged(atMilliseconds: 1_200)),
            [.scheduleRestart(milliseconds: 500)]
        )

        let restart = state.handle(.restartDelayElapsed(atMilliseconds: 1_700))
        XCTAssertEqual(restart.last, .restartCapture)
        XCTAssertEqual(
            restart.first,
            .record(
                .init(
                    track: .microphone,
                    code: .routeChanged,
                    severity: .information,
                    occurredAtMilliseconds: 1_200
                )
            )
        )

        XCTAssertEqual(
            state.handle(.restartSucceeded(atMilliseconds: 1_850)),
            [
                .record(
                    .init(
                        track: .microphone,
                        code: .routeRecovered,
                        severity: .information,
                        occurredAtMilliseconds: 1_850,
                        durationMilliseconds: 650
                    )
                )
            ]
        )
        XCTAssertEqual(state.state, .recording)
    }

    func testFailedRestartRecordsDegradationAndRetries() {
        var state = MicrophoneRouteRecoveryStateMachine()
        _ = state.handle(.start)
        _ = state.handle(.routeChanged(atMilliseconds: 2_000))
        _ = state.handle(.restartDelayElapsed(atMilliseconds: 2_500))

        let failed = state.handle(.restartFailed(atMilliseconds: 2_700))

        XCTAssertEqual(failed.last, .scheduleRetry(milliseconds: 2_000))
        XCTAssertEqual(
            failed.first,
            .record(
                .init(
                    track: .microphone,
                    code: .routeRecoveryFailed,
                    severity: .degraded,
                    occurredAtMilliseconds: 2_700,
                    durationMilliseconds: 700
                )
            )
        )
        XCTAssertEqual(
            state.handle(.retryDelayElapsed(atMilliseconds: 4_700)),
            [.restartCapture]
        )
    }

    func testStopCancelsFurtherRouteEffects() {
        var state = MicrophoneRouteRecoveryStateMachine()
        _ = state.handle(.start)
        _ = state.handle(.routeChanged(atMilliseconds: 100))
        XCTAssertEqual(state.handle(.stop), [])
        XCTAssertEqual(state.handle(.restartDelayElapsed(atMilliseconds: 600)), [])
        XCTAssertEqual(state.state, .stopped)
    }
}
