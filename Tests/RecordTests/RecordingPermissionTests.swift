@testable import Record
import RecordCore
import XCTest

@MainActor
final class RecordingPermissionTests: XCTestCase {
    func testScreenCommandRequestsMicrophoneThenScreenOnly() async {
        var events: [String] = []
        let microphone = FakeMicrophonePermissionProvider(
            state: .notDetermined,
            requestResult: true,
            onRequest: { events.append("microphone") }
        )
        let screen = FakeScreenPermissionProvider(
            isGranted: false,
            requestResult: true,
            onRequest: { events.append("screen") }
        )
        let systemAudio = FakeSystemAudioPermissionRegistrar {
            events.append("system-audio-only")
        }
        let controller = makeController(
            microphone: microphone,
            screen: screen,
            systemAudio: systemAudio
        )

        let result = await controller.prepare(for: .screen)

        XCTAssertEqual(result, .ready)
        XCTAssertEqual(events, ["microphone", "screen"])
        XCTAssertEqual(systemAudio.requestCount, 0)
    }

    func testAudioOnlyCommandRequestsMicrophoneThenSystemAudioOnly() async {
        var events: [String] = []
        let microphone = FakeMicrophonePermissionProvider(
            state: .notDetermined,
            requestResult: true,
            onRequest: { events.append("microphone") }
        )
        let screen = FakeScreenPermissionProvider(
            isGranted: false,
            requestResult: false,
            onRequest: { events.append("screen") }
        )
        let systemAudio = FakeSystemAudioPermissionRegistrar {
            events.append("system-audio-only")
        }
        let controller = makeController(
            microphone: microphone,
            screen: screen,
            systemAudio: systemAudio
        )

        let result = await controller.prepare(for: .audioOnly)

        XCTAssertEqual(result, .ready)
        XCTAssertEqual(events, ["microphone", "system-audio-only"])
        XCTAssertEqual(screen.requestCount, 0)
        XCTAssertNotNil(controller.takePreparedSystemAudioTap())
        XCTAssertNil(controller.takePreparedSystemAudioTap())
    }

    func testGrantedScreenAndMicrophoneStartWithoutAnyPrompt() async {
        let microphone = FakeMicrophonePermissionProvider(
            state: .authorized,
            requestResult: false
        )
        let screen = FakeScreenPermissionProvider(
            isGranted: true,
            requestResult: false
        )
        let systemAudio = FakeSystemAudioPermissionRegistrar()
        let controller = makeController(
            microphone: microphone,
            screen: screen,
            systemAudio: systemAudio
        )

        let result = await controller.prepare(for: .screen)

        XCTAssertEqual(result, .ready)
        XCTAssertEqual(microphone.requestCount, 0)
        XCTAssertEqual(screen.requestCount, 0)
        XCTAssertEqual(systemAudio.requestCount, 0)
    }

    func testDeniedMicrophoneStopsBeforeRequestingAnotherPermission() async {
        let microphone = FakeMicrophonePermissionProvider(
            state: .denied,
            requestResult: false
        )
        let screen = FakeScreenPermissionProvider(
            isGranted: false,
            requestResult: true
        )
        let systemAudio = FakeSystemAudioPermissionRegistrar()
        let controller = makeController(
            microphone: microphone,
            screen: screen,
            systemAudio: systemAudio
        )

        let result = await controller.prepare(for: .screen)

        XCTAssertEqual(result, .needsSettings(.microphone))
        XCTAssertEqual(microphone.requestCount, 0)
        XCTAssertEqual(screen.requestCount, 0)
        XCTAssertEqual(systemAudio.requestCount, 0)
    }

    func testScreenDenialWaitsForPrivacySettingsRestart() async {
        let controller = makeController(
            microphone: .init(state: .authorized, requestResult: false),
            screen: .init(isGranted: false, requestResult: false)
        )

        let result = await controller.prepare(for: .screen)

        XCTAssertEqual(result, .waitingForRestart(.screenAndSystemAudio))
    }

    func testSystemAudioFailureWaitsForPrivacySettingsRestart() async {
        let controller = makeController(
            microphone: .init(state: .authorized, requestResult: false),
            systemAudio: .init(status: -1)
        )

        let result = await controller.prepare(for: .audioOnly)

        XCTAssertEqual(result, .waitingForRestart(.systemAudioOnly))
    }

    func testSettingsPresenterReceivesTheExactBlocker() {
        var presented: RecordingPermissionBlocker?
        let controller = makeController(
            microphone: .init(state: .authorized, requestResult: false),
            settingsPresenter: {
                presented = $0
                return true
            }
        )

        XCTAssertTrue(controller.presentSettingsRequired(for: .systemAudioOnly))
        XCTAssertEqual(presented, .systemAudioOnly)
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
        microphone: FakeMicrophonePermissionProvider,
        screen: FakeScreenPermissionProvider =
            FakeScreenPermissionProvider(isGranted: true, requestResult: true),
        systemAudio: FakeSystemAudioPermissionRegistrar =
            FakeSystemAudioPermissionRegistrar(),
        settingsPresenter: @escaping RecordingPermissionController.SettingsPresenter = {
            _ in false
        }
    ) -> RecordingPermissionController {
        RecordingPermissionController(
            microphone: microphone,
            screen: screen,
            systemAudio: systemAudio,
            settingsPresenter: settingsPresenter
        )
    }
}

@MainActor
private final class FakeMicrophonePermissionProvider: MicrophonePermissionProviding {
    let state: MicrophonePermissionState
    private let requestResult: Bool
    private let onRequest: () -> Void
    private(set) var requestCount = 0

    init(
        state: MicrophonePermissionState,
        requestResult: Bool,
        onRequest: @escaping () -> Void = {}
    ) {
        self.state = state
        self.requestResult = requestResult
        self.onRequest = onRequest
    }

    func requestAccess() async -> Bool {
        requestCount += 1
        onRequest()
        return requestResult
    }
}

@MainActor
private final class FakeScreenPermissionProvider: ScreenRecordingPermissionProviding {
    let isGranted: Bool
    private let requestResult: Bool
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

@MainActor
private final class FakeSystemAudioPermissionRegistrar:
    SystemAudioPermissionRegistering
{
    private let status: OSStatus
    private let onRequest: () -> Void
    private var preparedTap: PreparedSystemAudioTap?
    private(set) var requestCount = 0

    init(status: OSStatus = noErr, onRequest: @escaping () -> Void = {}) {
        self.status = status
        self.onRequest = onRequest
    }

    @discardableResult
    func registerAccessRequest() -> OSStatus {
        requestCount += 1
        onRequest()
        if status == noErr, preparedTap == nil {
            preparedTap = PreparedSystemAudioTap(
                handle: .init(id: 42, uuid: UUID()),
                destroy: { _ in }
            )
        }
        return status
    }

    func takePreparedTap() -> PreparedSystemAudioTap? {
        defer { preparedTap = nil }
        return preparedTap
    }
}
