import Foundation
import RecordCore
import XCTest

final class RecordingReadinessTests: XCTestCase {
    func testMicrophoneOnlySetupDoesNotSuggestUnneededPermissionsOrRequireModel() {
        let readiness = RecordingReadiness(
            hasSaveFolder: true,
            audio: .init(includeSystemAudio: false), screenRecording: false,
            microphoneGranted: true, screenGranted: false, inputTested: false, modelInstalled: false
        )
        XCTAssertFalse(readiness.needsScreen)
        XCTAssertFalse(readiness.needsSystemAudio)
        XCTAssertTrue(readiness.checklist.contains("Screen access: not needed"))
        XCTAssertTrue(readiness.checklist.last?.hasPrefix("Optional:") == true)
    }
    func testSilentSamplesAreDistinctFromNoInputCallbacks() {
        let meter = AudioActivity()
        XCTAssertFalse(meter.hasReceivedSamples)
        meter.record(peak: 0)
        XCTAssertTrue(meter.hasReceivedSamples)
        XCTAssertEqual(meter.level(), 0)
        meter.reset()
        XCTAssertFalse(meter.hasReceivedSamples)
    }
    func testMeterRejectsNonfiniteValuesAndExpiresOldActivity() {
        let meter = AudioActivity()
        let now = Date(timeIntervalSince1970: 5)
        meter.record(peak: .infinity, at: now)
        XCTAssertEqual(meter.level(at: now), 0)
        meter.record(peak: 1, at: now)
        XCTAssertEqual(meter.level(at: now), 1)
        XCTAssertEqual(meter.level(at: now.addingTimeInterval(1)), 0)
    }
}
