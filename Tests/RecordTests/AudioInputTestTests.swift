import AVFoundation
@testable import Record
import RecordCore
import XCTest

final class AudioInputTestTests: XCTestCase {
    func testInputPickerHidesTheAppsEphemeralEngineRoute() {
        XCTAssertFalse(
            AudioInputDevices.isUserSelectable(
                uid: "CADefaultDeviceAggregate-123-0", processID: 123))
        XCTAssertTrue(AudioInputDevices.isUserSelectable(uid: "BuiltInMicrophone", processID: 123))
        XCTAssertTrue(AudioInputDevices.isUserSelectable(uid: "UserAggregate", processID: 123))
    }
    @MainActor
    func testInputTapRunsOffMainActorWithoutCapturingUIIsolation() async throws {
        let activity = AudioActivity()
        let finished = expectation(description: "audio callback")
        DispatchQueue.global().async {
            let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1)!
            buffer.frameLength = 1
            buffer.floatChannelData![0][0] = 1
            AudioInputTest.tap(activity: activity)(
                buffer, AVAudioTime(sampleTime: 0, atRate: 48_000))
            finished.fulfill()
        }
        await fulfillment(of: [finished], timeout: 3)
        XCTAssertEqual(activity.level(), 1)
    }
}
