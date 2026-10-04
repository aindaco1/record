import RecordCore
import XCTest

final class MicrophoneSelectionPolicyTests: XCTestCase {
    func testExplicitInputsAvoidIncompatibleDuplexVoiceProcessing() {
        XCTAssertTrue(MicrophoneSelectionPolicy.usesVoiceProcessing(requested: true, deviceID: nil))
        XCTAssertFalse(
            MicrophoneSelectionPolicy.usesVoiceProcessing(requested: false, deviceID: nil))
        XCTAssertFalse(
            MicrophoneSelectionPolicy.usesVoiceProcessing(requested: true, deviceID: "selected"))
    }
    func testInputChooserWaitsForPreservationAndDuplicateLossStopsOnlyOnce() {
        var recovery = SelectedMicrophoneRecovery()
        XCTAssertNil(recovery.handle(.recordingPreserved))
        XCTAssertEqual(recovery.handle(.deviceLost), .stopRecording)
        XCTAssertNil(recovery.handle(.deviceLost))
        XCTAssertEqual(recovery.handle(.recordingPreserved), .offerInput)
        XCTAssertNil(recovery.handle(.recordingPreserved))
    }

    func testExplicitDeviceLossCannotSubstituteAnotherAvailableMicrophone() {
        let selected = CaptureAudioConfiguration(microphoneDeviceID: "selected")
        XCTAssertTrue(
            MicrophoneSelectionPolicy.isAvailable(selected, deviceIDs: ["selected", "other"]))
        XCTAssertFalse(MicrophoneSelectionPolicy.isAvailable(selected, deviceIDs: ["other"]))
        XCTAssertTrue(MicrophoneSelectionPolicy.isAvailable(.init(), deviceIDs: ["other"]))
        XCTAssertTrue(
            MicrophoneSelectionPolicy.isAvailable(
                .init(includeMicrophone: false, microphoneDeviceID: "selected"), deviceIDs: []))
    }
}
