import AppKit
import CoreAudio
import CoreGraphics
import Foundation

protocol ScreenRecordingPermissionProviding {
    var isGranted: Bool { get }
    func requestAccess() -> Bool
}

final class SystemScreenRecordingPermissionProvider: ScreenRecordingPermissionProviding {
    var isGranted: Bool { CGPreflightScreenCaptureAccess() }

    func requestAccess() -> Bool {
        CGRequestScreenCaptureAccess()
    }
}

protocol SystemAudioPermissionRegistering {
    @discardableResult
    func registerAccessRequest() -> OSStatus
}

/// Registers Record with the system-audio-only TCC service without recording.
/// The temporary private tap is never attached to an aggregate device, given an
/// IO callback, or started, and is destroyed immediately if creation succeeds.
final class SystemAudioPermissionRegistrar: SystemAudioPermissionRegistering {
    @discardableResult
    func registerAccessRequest() -> OSStatus {
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.name = "Record permission setup"
        description.isPrivate = true
        description.muteBehavior = .unmuted

        var tapID = AudioObjectID(kAudioObjectUnknown)
        let status = AudioHardwareCreateProcessTap(description, &tapID)
        if status == noErr, tapID != kAudioObjectUnknown {
            _ = AudioHardwareDestroyProcessTap(tapID)
        }
        return status
    }
}

struct ScreenRecordingPermissionPresentation: Equatable, Sendable {
    let isGranted: Bool

    var menuTitle: String {
        isGranted ? "Recording Permissions…" : "Set Up Recording Permissions…"
    }

    var menuToolTip: String {
        if isGranted {
            return
                "Screen access is granted. Open setup to register or review system-audio-only access."
        }
        return
            "Register Record for screen and system-audio-only access in one guided setup."
    }

    var setupGuidance: String {
        """
        Record uses two separate macOS permissions:

        • Screen & System Audio Recording — for video recordings
        • System Audio Recording Only — for audio-only recordings

        Continue asks macOS to add Record to both permission lists. macOS may show one Apple confirmation for each list; choose Allow in each. Record will not capture or save anything during setup.

        System Settings will then open so you can review both entries. If macOS asks, restart Record after changing a permission.
        """
    }

    func captureDenialGuidance(restartRecommended: Bool) -> String {
        let nextStep =
            restartRecommended
            ? "If Record is already enabled, return to the feather menu and choose Restart Record."
            : "After enabling Record, return to the feather menu and choose Restart Record."
        return """
            Record needs Screen & System Audio Recording access to capture video. Audio-only recording still works.

            Open System Settings, enable Record under Privacy & Security › Screen & System Audio Recording, then return to Record. \(nextStep)
            """
    }
}

@MainActor
final class ScreenRecordingPermissionController {
    typealias SetupPresenter = @MainActor (_ guidance: String) -> Bool
    typealias DeniedPresenter = @MainActor (_ guidance: String) -> Void
    typealias SettingsOpener = @MainActor () -> Void

    private static let settingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
    )!

    private let provider: any ScreenRecordingPermissionProviding
    private let systemAudioRegistrar: any SystemAudioPermissionRegistering
    private let setupPresenter: SetupPresenter
    private let deniedPresenter: DeniedPresenter
    private let settingsOpener: SettingsOpener

    init(
        provider: any ScreenRecordingPermissionProviding =
            SystemScreenRecordingPermissionProvider(),
        systemAudioRegistrar: any SystemAudioPermissionRegistering =
            SystemAudioPermissionRegistrar(),
        setupPresenter: SetupPresenter? = nil,
        deniedPresenter: DeniedPresenter? = nil,
        settingsOpener: SettingsOpener? = nil
    ) {
        self.provider = provider
        self.systemAudioRegistrar = systemAudioRegistrar
        self.setupPresenter = setupPresenter ?? Self.presentSetup
        self.deniedPresenter = deniedPresenter ?? Self.presentDeniedAccess
        self.settingsOpener =
            settingsOpener ?? {
                NSWorkspace.shared.open(Self.settingsURL)
            }
    }

    var presentation: ScreenRecordingPermissionPresentation {
        ScreenRecordingPermissionPresentation(isGranted: provider.isGranted)
    }

    /// Screen recording starts only on a subsequent click after setup. This
    /// keeps permission registration distinct from capturing user content.
    func ensureAccess() -> Bool {
        if provider.isGranted { return true }
        setupPermissions()
        return false
    }

    /// Presents one Record-owned explanation, then registers both independent
    /// macOS TCC services in sequence. Apple may still present one native
    /// confirmation per service; applications cannot combine or pre-approve
    /// those system-owned decisions.
    func setupPermissions() {
        guard setupPresenter(presentation.setupGuidance) else { return }

        if !provider.isGranted {
            _ = provider.requestAccess()
        }
        let audioStatus = systemAudioRegistrar.registerAccessRequest()
        if audioStatus != noErr {
            FileHandle.standardError.write(
                Data(
                    "system audio permission registration returned OSStatus \(audioStatus)\n"
                        .utf8
                )
            )
        }
        settingsOpener()
    }

    func presentCaptureDenial() {
        deniedPresenter(
            ScreenRecordingPermissionPresentation(isGranted: false)
                .captureDenialGuidance(restartRecommended: true)
        )
    }

    private static func presentSetup(_ guidance: String) -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Set Up Recording Permissions"
        alert.informativeText = guidance
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Not Now")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private static func presentDeniedAccess(_ guidance: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Allow Screen Recording"
        alert.informativeText = guidance
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Not Now")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(settingsURL)
        }
    }
}
