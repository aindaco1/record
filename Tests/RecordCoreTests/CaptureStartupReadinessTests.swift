import RecordCore
import XCTest

final class CaptureStartupReadinessTests: XCTestCase {
    func testResumeRequiresVideoAndBothRequestedAudioWriters() {
        let readiness = CaptureStartupReadiness(audio: .init())
        XCTAssertFalse(readiness.isReady(processedTracks: []))
        XCTAssertFalse(readiness.isReady(processedTracks: [.screen]))
        XCTAssertFalse(readiness.isReady(processedTracks: [.screen, .systemAudio]))
        XCTAssertFalse(readiness.isReady(processedTracks: [.systemAudio, .microphone]))
        XCTAssertTrue(readiness.isReady(processedTracks: [.screen, .systemAudio, .microphone]))
    }

    func testDisabledAudioTracksCannotHoldStartupOpen() {
        let videoOnly = CaptureStartupReadiness(
            audio: .init(includeSystemAudio: false, includeMicrophone: false)
        )
        XCTAssertTrue(videoOnly.isReady(processedTracks: [.screen]))
        let microphone = CaptureStartupReadiness(
            audio: .init(includeSystemAudio: false, includeMicrophone: true)
        )
        XCTAssertFalse(microphone.isReady(processedTracks: [.screen]))
        XCTAssertTrue(microphone.isReady(processedTracks: [.screen, .microphone]))
    }
}
