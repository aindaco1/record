@testable import Record
import RecordCore
import XCTest

@MainActor
final class ScreenRecordingPermissionTests: XCTestCase {
    func testGrantedPermissionDoesNotRequestOrPresentGuidance() {
        let provider = FakePermissionProvider(isGranted: true, requestResult: false)
        var presented: [String] = []
        let controller = ScreenRecordingPermissionController(provider: provider) {
            presented.append($0)
        }

        XCTAssertTrue(controller.ensureAccess())
        XCTAssertEqual(provider.requestCount, 0)
        XCTAssertTrue(presented.isEmpty)
        XCTAssertEqual(
            controller.presentation.menuTitle,
            "Screen Recording Permission: Granted"
        )
    }

    func testInitialDeniedRequestReliesOnNativePromptWithoutStackingGuidance() {
        let provider = FakePermissionProvider(
            isGranted: false,
            hasRequestedAccess: false,
            requestResult: false
        )
        var presented: [String] = []
        let controller = ScreenRecordingPermissionController(provider: provider) {
            presented.append($0)
        }

        XCTAssertFalse(controller.ensureAccess())
        XCTAssertEqual(provider.requestCount, 1)
        XCTAssertTrue(provider.hasRequestedAccess)
        XCTAssertTrue(presented.isEmpty)
        XCTAssertEqual(
            controller.presentation.menuTitle,
            "Open Screen Recording Settings…"
        )
    }

    func testRetryAfterNativeRequestShowsOneHumanGuidanceWithoutRequestingAgain() {
        let provider = FakePermissionProvider(
            isGranted: false,
            hasRequestedAccess: true,
            requestResult: false
        )
        var presented: [String] = []
        let controller = ScreenRecordingPermissionController(provider: provider) {
            presented.append($0)
        }

        XCTAssertFalse(controller.ensureAccess())
        XCTAssertEqual(provider.requestCount, 0)
        XCTAssertEqual(presented.count, 1)
        XCTAssertTrue(presented[0].contains("Audio-only recording still works"))
        XCTAssertTrue(presented[0].contains("Restart Record"))
        XCTAssertTrue(presented[0].contains("System Audio Recording Only"))
        XCTAssertFalse(presented[0].contains("permissionDenied"))
    }

    func testSuccessfulRequestContinuesWithoutFailureAlert() {
        let provider = FakePermissionProvider(isGranted: false, requestResult: true)
        var presented = false
        let controller = ScreenRecordingPermissionController(provider: provider) { _ in
            presented = true
        }

        XCTAssertTrue(controller.ensureAccess())
        XCTAssertEqual(provider.requestCount, 1)
        XCTAssertFalse(presented)
    }

    func testCaptureDenialExplainsAlreadyEnabledRestartCase() {
        let provider = FakePermissionProvider(isGranted: false, requestResult: false)
        var guidance: String?
        let controller = ScreenRecordingPermissionController(provider: provider) {
            guidance = $0
        }

        controller.presentCaptureDenial()

        XCTAssertTrue(guidance?.contains("already enabled") == true)
        XCTAssertTrue(guidance?.contains("Restart Record") == true)
    }

    func testCaptureFailuresMapToHumanReadableMessages() {
        let permission = VideoRecordingSession.SessionError.captureFailed(
            CaptureFailure(
                code: .permissionDenied,
                summary: "debug-only failure description"
            )
        )
        let encoder = VideoRecordingSession.SessionError.captureFailed(
            CaptureFailure(code: .encoderFailed, summary: "opaque encoder error")
        )

        let permissionMessage = AppController.startFailureMessage(for: permission)
        let encoderMessage = AppController.startFailureMessage(for: encoder)

        XCTAssertEqual(
            permissionMessage,
            "Screen Recording permission is required. Audio-only recording still works."
        )
        XCTAssertTrue(encoderMessage.contains("local video file"))
        XCTAssertFalse(permissionMessage.contains("permissionDenied"))
        XCTAssertFalse(encoderMessage.contains("opaque encoder error"))
    }
}

private final class FakePermissionProvider: ScreenRecordingPermissionProviding {
    let isGranted: Bool
    private(set) var hasRequestedAccess: Bool
    let requestResult: Bool
    private(set) var requestCount = 0

    init(
        isGranted: Bool,
        hasRequestedAccess: Bool = false,
        requestResult: Bool
    ) {
        self.isGranted = isGranted
        self.hasRequestedAccess = hasRequestedAccess
        self.requestResult = requestResult
    }

    func requestAccess() -> Bool {
        requestCount += 1
        hasRequestedAccess = true
        return requestResult
    }
}
