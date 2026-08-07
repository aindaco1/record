import RecordCore
import XCTest

final class CaptureHealthTests: XCTestCase {
    func testPostRestartGuardDefersSelfNotificationAndAcceptsRecentCallbacks() {
        var guardState = MicrophoneRestartLivenessGuard()
        guardState.begin(atMilliseconds: 10_000, voiceProcessingEnabled: true)

        XCTAssertTrue(
            guardState.shouldDeferEngineConfigurationChange(atMilliseconds: 11_400)
        )
        XCTAssertEqual(
            guardState.evaluate(
                atMilliseconds: 12_000,
                lastCallbackAtMilliseconds: 11_900,
                captureIsRunning: true
            ),
            .healthy
        )
        XCTAssertFalse(
            guardState.shouldDeferEngineConfigurationChange(atMilliseconds: 12_001)
        )
    }

    func testPostRestartGuardFallsBackOnceWhenVoiceProcessingStopsCallbacks() {
        var guardState = MicrophoneRestartLivenessGuard()
        guardState.begin(atMilliseconds: 20_000, voiceProcessingEnabled: true)

        XCTAssertTrue(
            guardState.shouldDeferEngineConfigurationChange(atMilliseconds: 21_388)
        )
        XCTAssertEqual(
            guardState.evaluate(
                atMilliseconds: 22_000,
                lastCallbackAtMilliseconds: 21_900,
                captureIsRunning: false
            ),
            .fallBackToRaw
        )
        XCTAssertNil(
            guardState.evaluate(
                atMilliseconds: 24_000,
                lastCallbackAtMilliseconds: nil,
                captureIsRunning: false
            )
        )
    }

    func testPostRestartGuardRetriesWhenRawCaptureHasNoRecentCallbacks() {
        var guardState = MicrophoneRestartLivenessGuard()
        guardState.begin(atMilliseconds: 30_000, voiceProcessingEnabled: false)

        XCTAssertEqual(
            guardState.evaluate(
                atMilliseconds: 32_000,
                lastCallbackAtMilliseconds: nil,
                captureIsRunning: false
            ),
            .retryCapture
        )
    }

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
