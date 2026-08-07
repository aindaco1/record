import AppKit
import CoreGraphics
import Foundation

protocol ScreenRecordingPermissionProviding {
    var isGranted: Bool { get }
    var hasRequestedAccess: Bool { get }
    func requestAccess() -> Bool
}

final class SystemScreenRecordingPermissionProvider: ScreenRecordingPermissionProviding {
    private static let requestRecordedKey =
        "screenRecordingPermissionRequestRecorded"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isGranted: Bool { CGPreflightScreenCaptureAccess() }
    var hasRequestedAccess: Bool { defaults.bool(forKey: Self.requestRecordedKey) }

    func requestAccess() -> Bool {
        // Record this before entering TCC because the native prompt can block
        // and the process may be restarted immediately after the response.
        defaults.set(true, forKey: Self.requestRecordedKey)
        return CGRequestScreenCaptureAccess()
    }
}

struct ScreenRecordingPermissionPresentation: Equatable, Sendable {
    let isGranted: Bool
    let hasRequestedAccess: Bool

    var menuTitle: String {
        if isGranted { return "Screen Recording Permission: Granted" }
        return hasRequestedAccess
            ? "Open Screen Recording Settings…"
            : "Grant Screen Recording Permission…"
    }

    var menuToolTip: String {
        if isGranted { return "Record can capture your screen." }
        if hasRequestedAccess {
            return
                "Permission was already requested. Enable Record in System Settings, then restart it."
        }
        return
            "Requests screen access. macOS groups it under Screen & System Audio Recording."
    }

    func guidance(restartRecommended: Bool) -> String {
        let nextStep =
            restartRecommended
            ? "If Record is already enabled, return to the feather menu and choose Restart Record."
            : "After enabling Record, return to the feather menu and choose Restart Record."
        return """
            Record needs Screen Recording access to capture video. Audio-only recording still works.

            macOS groups screen access under Privacy & Security › Screen & System Audio Recording. The separate System Audio Recording Only permission is requested only when an audio recording starts.

            Open System Settings, enable Record, then return to Record. \(nextStep)
            """
    }
}

@MainActor
final class ScreenRecordingPermissionController {
    typealias DeniedPresenter = @MainActor (_ guidance: String) -> Void

    private static let settingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
    )!

    private let provider: any ScreenRecordingPermissionProviding
    private let deniedPresenter: DeniedPresenter

    init(
        provider: any ScreenRecordingPermissionProviding =
            SystemScreenRecordingPermissionProvider(),
        deniedPresenter: DeniedPresenter? = nil
    ) {
        self.provider = provider
        self.deniedPresenter = deniedPresenter ?? Self.presentDeniedAccess
    }

    var presentation: ScreenRecordingPermissionPresentation {
        ScreenRecordingPermissionPresentation(
            isGranted: provider.isGranted,
            hasRequestedAccess: provider.hasRequestedAccess
        )
    }

    func ensureAccess() -> Bool {
        if provider.isGranted { return true }
        if !provider.hasRequestedAccess {
            // CGRequestScreenCaptureAccess presents Apple's native prompt.
            // Do not stack a second Record alert while that prompt is active.
            return provider.requestAccess()
        }
        deniedPresenter(
            ScreenRecordingPermissionPresentation(
                isGranted: false,
                hasRequestedAccess: true
            ).guidance(
                restartRecommended: false
            )
        )
        return false
    }

    func presentCaptureDenial() {
        deniedPresenter(
            ScreenRecordingPermissionPresentation(
                isGranted: false,
                hasRequestedAccess: true
            ).guidance(
                restartRecommended: true
            )
        )
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
