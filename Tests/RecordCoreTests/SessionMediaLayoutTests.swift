@testable import RecordCore
import XCTest

final class SessionMediaLayoutTests: XCTestCase {
    func testCanonicalFilenamesStayConsistentAcrossCaptureAndFinalization() {
        XCTAssertEqual(
            SessionMediaLayout.filename(for: .screen, stage: .capture),
            "recording.mov"
        )
        XCTAssertEqual(
            SessionMediaLayout.filename(for: .screen, stage: .finalized),
            "recording.mov"
        )
        XCTAssertEqual(
            SessionMediaLayout.filename(for: .microphone, stage: .capture),
            "mic.caf"
        )
        XCTAssertEqual(
            SessionMediaLayout.filename(for: .microphone, stage: .finalized),
            "mic.wav"
        )
        XCTAssertEqual(
            SessionMediaLayout.filename(for: .systemAudio, stage: .capture),
            "system.caf"
        )
        XCTAssertEqual(
            SessionMediaLayout.filename(for: .systemAudio, stage: .finalized),
            "system.wav"
        )
        XCTAssertNil(SessionMediaLayout.filename(for: .camera, stage: .capture))
        XCTAssertNil(SessionMediaLayout.filename(for: .camera, stage: .finalized))
    }

    func testCanonicalTracksOwnAnonymousSpeakerDefaults() throws {
        let microphone = try XCTUnwrap(
            SessionMediaLayout.track(for: .microphone, stage: .finalized)
        )
        let system = try XCTUnwrap(
            SessionMediaLayout.track(for: .systemAudio, stage: .finalized)
        )
        let screen = try XCTUnwrap(SessionMediaLayout.track(for: .screen, stage: .finalized))

        XCTAssertEqual(microphone.speaker, "me")
        XCTAssertEqual(system.speaker, "them")
        XCTAssertNil(screen.speaker)
    }
}
