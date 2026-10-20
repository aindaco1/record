import RecordCore
import XCTest

final class MicrophoneVoiceProcessingPolicyTests: XCTestCase {
    func testZoomAlreadyOpenPreventsVoiceProcessingBeforeCapture() {
        var policy = MicrophoneVoiceProcessingPolicy()
        XCTAssertTrue(policy.observeZoom(isRunning: true))
        XCTAssertFalse(policy.usesVoiceProcessing(deviceID: nil))
        XCTAssertTrue(policy.bypassedForZoom)
    }

    func testZoomLaunchLatchesRawThroughQuitRelaunchAndRouteRecovery() {
        var policy = MicrophoneVoiceProcessingPolicy()
        XCTAssertFalse(policy.observeZoom(isRunning: false))
        XCTAssertTrue(policy.usesVoiceProcessing(deviceID: nil))
        XCTAssertTrue(policy.observeZoom(isRunning: true))
        for running in [true, false, true, false] {
            XCTAssertFalse(policy.observeZoom(isRunning: running))
            XCTAssertFalse(policy.usesVoiceProcessing(deviceID: nil))
        }
        policy.reset()
        policy.observeZoom(isRunning: false)
        XCTAssertTrue(policy.usesVoiceProcessing(deviceID: nil))
    }

    func testManualOffAndExplicitMicrophoneAlwaysUseRawInput() {
        var off = MicrophoneVoiceProcessingPolicy(requested: false)
        XCTAssertFalse(off.observeZoom(isRunning: true))
        XCTAssertFalse(off.usesVoiceProcessing(deviceID: nil))
        XCTAssertFalse(MicrophoneVoiceProcessingPolicy().usesVoiceProcessing(deviceID: "external"))
    }

    func testAutomaticProtectionCanBeDisabledWithoutDisablingAppleProcessing() {
        var policy = MicrophoneVoiceProcessingPolicy(disableForZoom: false)
        XCTAssertFalse(policy.observeZoom(isRunning: true))
        XCTAssertTrue(policy.usesVoiceProcessing(deviceID: nil))
        XCTAssertFalse(policy.bypassedForZoom)
    }

    func testNewCaptureChecksZoomAgainAfterReset() {
        var policy = MicrophoneVoiceProcessingPolicy()
        policy.observeZoom(isRunning: true)
        policy.reset()
        XCTAssertTrue(policy.observeZoom(isRunning: true))
        XCTAssertFalse(policy.usesVoiceProcessing(deviceID: nil))
    }
}
