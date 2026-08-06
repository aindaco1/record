import RecordCapture
import RecordCore
import ScreenCaptureKit
import XCTest

final class ScreenCaptureFailureMapperTests: XCTestCase {
    func testMapsPermissionSourceAndAudioFailuresWithoutPrivateDetails() {
        XCTAssertEqual(
            failure(.userDeclined).code,
            .permissionDenied
        )
        XCTAssertEqual(
            failure(.systemStoppedStream).code,
            .sourceUnavailable
        )
        XCTAssertEqual(
            failure(.failedToStartMicrophoneCapture).code,
            .deviceDisconnected
        )
    }

    func testNativeUserStopBecomesAStopRequestInsteadOfFailure() {
        let error = NSError(
            domain: SCStreamErrorDomain,
            code: SCStreamError.Code.userStopped.rawValue
        )

        XCTAssertEqual(
            ScreenCaptureFailureMapper.event(for: error),
            .stopRequested
        )
    }

    func testUnknownErrorsFailClosed() {
        let error = NSError(domain: "example", code: 1)

        XCTAssertEqual(
            ScreenCaptureFailureMapper.failure(for: error),
            CaptureFailure(
                code: .internalFailure,
                summary: "screen capture stopped unexpectedly"
            )
        )
    }

    private func failure(_ code: SCStreamError.Code) -> CaptureFailure {
        ScreenCaptureFailureMapper.failure(
            for: NSError(domain: SCStreamErrorDomain, code: code.rawValue)
        )
    }
}
