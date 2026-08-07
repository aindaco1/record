import AppKit
import CoreGraphics
import Foundation

protocol ScreenRecordingPermissionProviding: Sendable {
    var isGranted: Bool { get }
    func requestAccess() -> Bool
}

struct SystemScreenRecordingPermissionProvider: ScreenRecordingPermissionProviding {
    var isGranted: Bool { CGPreflightScreenCaptureAccess() }

    func requestAccess() -> Bool {
        CGRequestScreenCaptureAccess()
    }
}

struct ScreenRecordingPermissionPresentation: Equatable, Sendable {
    let isGranted: Bool

    var menuTitle: String {
        isGranted
            ? "Screen Recording Permission: Granted"
            : "Grant Screen Recording Permission…"
    }

    var menuToolTip: String {
        isGranted
            ? "Record can capture your screen."
            : "Required only for video. Audio-only recording remains available."
    }

    func guidance(restartRecommended: Bool) -> String {
        let nextStep =
            restartRecommended
            ? "If Record is already enabled, return to the feather menu and choose Restart Record."
            : "After enabling Record, return to the feather menu and choose Restart Record."
        return """
            Record needs Screen Recording access to capture video. Audio-only recording still works.

            Open System Settings, enable Record under Privacy & Security › Screen & System Audio Recording, then return to Record. \(nextStep)
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
        ScreenRecordingPermissionPresentation(isGranted: provider.isGranted)
    }

    func ensureAccess() -> Bool {
        if provider.isGranted { return true }
        if provider.requestAccess() { return true }
        deniedPresenter(
            ScreenRecordingPermissionPresentation(isGranted: false).guidance(
                restartRecommended: false
            )
        )
        return false
    }

    func presentCaptureDenial() {
        deniedPresenter(
            ScreenRecordingPermissionPresentation(isGranted: false).guidance(
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
