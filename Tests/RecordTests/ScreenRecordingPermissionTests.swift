@testable import Record
import RecordCore
import XCTest

@MainActor
final class ScreenRecordingPermissionTests: XCTestCase {
    func testGrantedPermissionStartsWithoutShowingSetup() {
        let provider = FakePermissionProvider(isGranted: true, requestResult: false)
        let audioRegistrar = FakeSystemAudioPermissionRegistrar()
        var setupCount = 0
        let controller = makeController(
            provider: provider,
            audioRegistrar: audioRegistrar,
            setupPresenter: { _ in
                setupCount += 1
                return true
            }
        )

        XCTAssertTrue(controller.ensureAccess())
        XCTAssertEqual(provider.requestCount, 0)
        XCTAssertEqual(audioRegistrar.requestCount, 0)
        XCTAssertEqual(setupCount, 0)
        XCTAssertEqual(controller.presentation.menuTitle, "Recording Permissions…")
    }

    func testSetupPresentsOneMessageThenRegistersBothPermissionsInOrder() {
        var events: [String] = []
        let provider = FakePermissionProvider(
            isGranted: false,
            requestResult: false,
            onRequest: { events.append("screen") }
        )
        let audioRegistrar = FakeSystemAudioPermissionRegistrar {
            events.append("system-audio")
        }
        let controller = makeController(
            provider: provider,
            audioRegistrar: audioRegistrar,
            setupPresenter: { guidance in
                events.append("message")
                XCTAssertTrue(guidance.contains("Screen & System Audio Recording"))
                XCTAssertTrue(guidance.contains("System Audio Recording Only"))
                XCTAssertTrue(guidance.contains("will not capture or save anything"))
                return true
            },
            settingsOpener: { events.append("settings") }
        )

        controller.setupPermissions()

        XCTAssertEqual(events, ["message", "screen", "system-audio", "settings"])
        XCTAssertEqual(provider.requestCount, 1)
        XCTAssertEqual(audioRegistrar.requestCount, 1)
    }

    func testCancelledSetupRequestsNothingAndDoesNotOpenSettings() {
        let provider = FakePermissionProvider(isGranted: false, requestResult: false)
        let audioRegistrar = FakeSystemAudioPermissionRegistrar()
        var settingsOpenCount = 0
        let controller = makeController(
            provider: provider,
            audioRegistrar: audioRegistrar,
            setupPresenter: { _ in false },
            settingsOpener: { settingsOpenCount += 1 }
        )

        controller.setupPermissions()

        XCTAssertEqual(provider.requestCount, 0)
        XCTAssertEqual(audioRegistrar.requestCount, 0)
        XCTAssertEqual(settingsOpenCount, 0)
    }

    func testSetupStillRegistersSystemAudioWhenScreenIsAlreadyGranted() {
        let provider = FakePermissionProvider(isGranted: true, requestResult: true)
        let audioRegistrar = FakeSystemAudioPermissionRegistrar()
        var settingsOpenCount = 0
        let controller = makeController(
            provider: provider,
            audioRegistrar: audioRegistrar,
            setupPresenter: { _ in true },
            settingsOpener: { settingsOpenCount += 1 }
        )

        controller.setupPermissions()

        XCTAssertEqual(provider.requestCount, 0)
        XCTAssertEqual(audioRegistrar.requestCount, 1)
        XCTAssertEqual(settingsOpenCount, 1)
    }

    func testInitialScreenStartRunsSetupButDoesNotCaptureOnSameClick() {
        let provider = FakePermissionProvider(isGranted: false, requestResult: true)
        let audioRegistrar = FakeSystemAudioPermissionRegistrar()
        let controller = makeController(
            provider: provider,
            audioRegistrar: audioRegistrar,
            setupPresenter: { _ in true }
        )

        XCTAssertFalse(controller.ensureAccess())
        XCTAssertEqual(provider.requestCount, 1)
        XCTAssertEqual(audioRegistrar.requestCount, 1)
    }

    func testCaptureDenialExplainsAlreadyEnabledRestartCase() {
        let provider = FakePermissionProvider(isGranted: false, requestResult: false)
        var guidance: String?
        let controller = makeController(
            provider: provider,
            deniedPresenter: { guidance = $0 }
        )

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

    private func makeController(
        provider: FakePermissionProvider,
        audioRegistrar: FakeSystemAudioPermissionRegistrar =
            FakeSystemAudioPermissionRegistrar(),
        setupPresenter: @escaping ScreenRecordingPermissionController.SetupPresenter = {
            _ in false
        },
        deniedPresenter: @escaping ScreenRecordingPermissionController.DeniedPresenter = {
            _ in
        },
        settingsOpener: @escaping ScreenRecordingPermissionController.SettingsOpener = {}
    ) -> ScreenRecordingPermissionController {
        ScreenRecordingPermissionController(
            provider: provider,
            systemAudioRegistrar: audioRegistrar,
            setupPresenter: setupPresenter,
            deniedPresenter: deniedPresenter,
            settingsOpener: settingsOpener
        )
    }
}

private final class FakePermissionProvider: ScreenRecordingPermissionProviding {
    let isGranted: Bool
    let requestResult: Bool
    private let onRequest: () -> Void
    private(set) var requestCount = 0

    init(
        isGranted: Bool,
        requestResult: Bool,
        onRequest: @escaping () -> Void = {}
    ) {
        self.isGranted = isGranted
        self.requestResult = requestResult
        self.onRequest = onRequest
    }

    func requestAccess() -> Bool {
        requestCount += 1
        onRequest()
        return requestResult
    }
}

private final class FakeSystemAudioPermissionRegistrar:
    SystemAudioPermissionRegistering
{
    private let onRequest: () -> Void
    private(set) var requestCount = 0

    init(onRequest: @escaping () -> Void = {}) {
        self.onRequest = onRequest
    }

    @discardableResult
    func registerAccessRequest() -> OSStatus {
        requestCount += 1
        onRequest()
        return noErr
    }
}
