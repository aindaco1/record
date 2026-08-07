import AVFoundation
@testable import Record
import XCTest

final class MicRecorderTests: XCTestCase {
    func testUnsupportedFormatErrorSnapshotsSendableDiagnostic() throws {
        let format = try XCTUnwrap(
            AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 48_000,
                channels: 2,
                interleaved: false
            )
        )

        let error = MicRecorder.RecorderError.unsupportedFormat(format)

        requireSendable(error)
        XCTAssertTrue(error.description.contains("can't downmix mic format"))
        XCTAssertTrue(error.description.contains("48000"))
    }

    private func requireSendable<T: Sendable>(_ value: T) {}
}
