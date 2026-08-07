import AppKit
import AVFoundation
import CoreAudio
import CoreGraphics
import Foundation

enum MicrophonePermissionState: Equatable, Sendable {
    case authorized
    case notDetermined
    case denied
}

@MainActor
protocol MicrophonePermissionProviding {
    var state: MicrophonePermissionState { get }
    func requestAccess() async -> Bool
}

@MainActor
final class SystemMicrophonePermissionProvider: MicrophonePermissionProviding {
    var state: MicrophonePermissionState {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: .authorized
        case .notDetermined: .notDetermined
        case .denied, .restricted: .denied
        @unknown default: .denied
        }
    }

    func requestAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }
}

@MainActor
protocol ScreenRecordingPermissionProviding {
    var isGranted: Bool { get }
    func requestAccess() -> Bool
}

@MainActor
final class SystemScreenRecordingPermissionProvider: ScreenRecordingPermissionProviding {
    var isGranted: Bool { CGPreflightScreenCaptureAccess() }

    func requestAccess() -> Bool {
        CGRequestScreenCaptureAccess()
    }
}

@MainActor
protocol SystemAudioPermissionRegistering {
    @discardableResult
    func registerAccessRequest() -> OSStatus
    func takePreparedTap() -> PreparedSystemAudioTap?
}

/// Requests the system-audio-only TCC service without beginning capture. A
/// successful private tap is transferred into the imminent recording so the
/// permission check and capture do not initialize Core Audio twice.
@MainActor
final class SystemAudioPermissionRegistrar: SystemAudioPermissionRegistering {
    private var preparedTap: PreparedSystemAudioTap?

    @discardableResult
    func registerAccessRequest() -> OSStatus {
        preparedTap = nil
        do {
            preparedTap = try PreparedSystemAudioTap.create(
                name: "Record system audio"
            )
            return noErr
        } catch let error as PreparedSystemAudioTap.CreationError {
            return error.status
        } catch {
            return kAudioHardwareUnspecifiedError
        }
    }

    func takePreparedTap() -> PreparedSystemAudioTap? {
        defer { preparedTap = nil }
        return preparedTap
    }
}

enum RecordingPermissionBlocker: Equatable, Sendable {
    case microphone
    case screenAndSystemAudio
    case systemAudioOnly

    fileprivate var alertTitle: String {
        switch self {
        case .microphone: "Allow Microphone Access"
        case .screenAndSystemAudio: "Allow Screen Recording"
        case .systemAudioOnly: "Allow System Audio Recording"
        }
    }

    fileprivate var guidance: String {
        switch self {
        case .microphone:
            "Enable Record under Privacy & Security › Microphone. Record will restart after you change the permission."
        case .screenAndSystemAudio:
            "Enable Record under Privacy & Security › Screen & System Audio Recording. Record will restart after you change the permission."
        case .systemAudioOnly:
            "Enable Record under Privacy & Security › Screen & System Audio Recording › System Audio Recording Only. Record will restart after you change the permission."
        }
    }

    fileprivate var settingsURL: URL {
        let pane = self == .microphone ? "Privacy_Microphone" : "Privacy_ScreenCapture"
        return URL(
            string: "x-apple.systempreferences:com.apple.preference.security?\(pane)"
        )!
    }
}

enum RecordingPermissionPreparation: Equatable, Sendable {
    case ready
    case waitingForRestart(RecordingPermissionBlocker)
    case needsSettings(RecordingPermissionBlocker)
}

enum RecordingPermissionFlowAction: Equatable, Sendable {
    case request
    case restart
}

/// Small deterministic state machine for the handoff between a Start command,
/// native TCC UI, and a possible process replacement.
struct RecordingPermissionFlowState: Equatable, Sendable {
    private(set) var pendingMode: RecordingMode?

    mutating func begin(
        _ mode: RecordingMode,
        resumingAfterRestart: Bool
    ) -> RecordingPermissionFlowAction {
        if pendingMode == mode, !resumingAfterRestart {
            return .restart
        }
        pendingMode = mode
        return .request
    }

    mutating func arm(_ mode: RecordingMode) {
        pendingMode = mode
    }

    mutating func clear() {
        pendingMode = nil
    }
}

/// Requests only the permissions required by the recording command the user
/// selected. Microphone access is requested first and awaited so macOS never
/// stacks its microphone prompt on top of a screen/system-audio prompt.
@MainActor
final class RecordingPermissionController {
    typealias SettingsPresenter = @MainActor (RecordingPermissionBlocker) -> Bool

    private let microphone: any MicrophonePermissionProviding
    private let screen: any ScreenRecordingPermissionProviding
    private let systemAudio: any SystemAudioPermissionRegistering
    private let settingsPresenter: SettingsPresenter

    init(
        microphone: any MicrophonePermissionProviding =
            SystemMicrophonePermissionProvider(),
        screen: any ScreenRecordingPermissionProviding =
            SystemScreenRecordingPermissionProvider(),
        systemAudio: any SystemAudioPermissionRegistering =
            SystemAudioPermissionRegistrar(),
        settingsPresenter: SettingsPresenter? = nil
    ) {
        self.microphone = microphone
        self.screen = screen
        self.systemAudio = systemAudio
        self.settingsPresenter = settingsPresenter ?? Self.presentSettingsRequired
    }

    func prepare(for mode: RecordingMode) async -> RecordingPermissionPreparation {
        switch microphone.state {
        case .authorized:
            break
        case .notDetermined:
            guard await microphone.requestAccess() else {
                return .needsSettings(.microphone)
            }
        case .denied:
            return .needsSettings(.microphone)
        }

        switch mode {
        case .screen:
            if screen.isGranted { return .ready }
            return screen.requestAccess()
                ? .ready
                : .waitingForRestart(.screenAndSystemAudio)
        case .audioOnly:
            let status = systemAudio.registerAccessRequest()
            guard status == noErr else {
                FileHandle.standardError.write(
                    Data(
                        "system audio permission check returned OSStatus \(status)\n".utf8
                    )
                )
                return .waitingForRestart(.systemAudioOnly)
            }
            return .ready
        }
    }

    /// Returns true only when the user chose to open the relevant pane. The
    /// caller uses that signal to keep or discard its pending recording intent.
    func presentSettingsRequired(for blocker: RecordingPermissionBlocker) -> Bool {
        settingsPresenter(blocker)
    }

    func takePreparedSystemAudioTap() -> PreparedSystemAudioTap? {
        systemAudio.takePreparedTap()
    }

    private static func presentSettingsRequired(
        _ blocker: RecordingPermissionBlocker
    ) -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = blocker.alertTitle
        alert.informativeText = blocker.guidance
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Not Now")
        guard alert.runModal() == .alertFirstButtonReturn else { return false }
        NSWorkspace.shared.open(blocker.settingsURL)
        return true
    }
}

/// Carries a user-initiated Start command across the one process replacement
/// macOS requires after a privacy toggle. Values are consumed exactly once so
/// an ordinary later launch can never begin recording unexpectedly.
@MainActor
final class PendingRecordingIntentStore {
    static let key = "recording.pendingAfterPrivacyRestart"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func save(_ mode: RecordingMode) {
        defaults.set(mode.rawValue, forKey: Self.key)
    }

    func consume() -> RecordingMode? {
        defer { defaults.removeObject(forKey: Self.key) }
        return defaults.string(forKey: Self.key).flatMap(RecordingMode.init(rawValue:))
    }

    func clear() {
        defaults.removeObject(forKey: Self.key)
    }
}
