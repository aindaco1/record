import RecordCore
import Foundation

/// One deterministic rendering contract for every recording phase. AppKit
/// applies this value to menu items; transition-specific code only chooses the
/// phase and supplies dynamic text.
struct RecordingMenuPresentation: Equatable {
    let stateTitle: String
    let toggleTitle: String
    let pauseResumeTitle: String
    let toggleEnabled: Bool
    let pauseResumeVisible: Bool
    let pauseResumeEnabled: Bool
    let audioOnlyEnabled: Bool
    let screenSourceEnabled: Bool
    let exportFolderEnabled: Bool
    let capturePrivacyEnabled: Bool
    let recordingIndicatorActive: Bool
    let clearsCaptureHealth: Bool

    static let idle = RecordingMenuPresentation(
        stateTitle: L10n.text("idle"),
        toggleTitle: L10n.text("Start screen recording"),
        pauseResumeTitle: L10n.text("Pause screen recording"),
        toggleEnabled: true,
        pauseResumeVisible: false,
        pauseResumeEnabled: false,
        audioOnlyEnabled: true,
        screenSourceEnabled: true,
        exportFolderEnabled: true,
        capturePrivacyEnabled: true,
        recordingIndicatorActive: false,
        clearsCaptureHealth: true
    )

    static func recording(
        mode: RecordingMode,
        elapsed: String,
        healthNote: String?
    ) -> Self {
        let health = healthNote.map { " · \($0)" } ?? ""
        return RecordingMenuPresentation(
            stateTitle: L10n.format(
                "● %@ recording · %@%@", L10n.text(mode.displayName), elapsed, health),
            toggleTitle: L10n.text("Stop recording"),
            pauseResumeTitle: L10n.text("Pause screen recording"),
            toggleEnabled: true,
            pauseResumeVisible: mode == .screen,
            pauseResumeEnabled: mode == .screen,
            audioOnlyEnabled: false,
            screenSourceEnabled: false,
            exportFolderEnabled: false,
            capturePrivacyEnabled: false,
            recordingIndicatorActive: true,
            clearsCaptureHealth: false
        )
    }

    static func requestingPermissions(for mode: RecordingMode) -> Self {
        busy(
            stateTitle: L10n.format(
                "waiting for %@ recording permissions…", L10n.text(mode.displayName)),
            toggleTitle: L10n.text("Start screen recording"),
            clearsCaptureHealth: true
        )
    }

    static let preparingScreenRecording = busy(
        stateTitle: L10n.text("preparing screen recording…"),
        toggleTitle: L10n.text("Preparing screen recording…"),
        clearsCaptureHealth: true
    )

    static func stoppingScreenRecording(
        captureStarted: Bool,
        indicatorActive: Bool
    ) -> Self {
        RecordingMenuPresentation(
            stateTitle: L10n.text("stopping recording…"),
            toggleTitle: L10n.text("Stopping recording…"),
            pauseResumeTitle: L10n.text("Pause screen recording"),
            toggleEnabled: false,
            pauseResumeVisible: captureStarted,
            pauseResumeEnabled: false,
            audioOnlyEnabled: false,
            screenSourceEnabled: false,
            exportFolderEnabled: false,
            capturePrivacyEnabled: false,
            recordingIndicatorActive: indicatorActive,
            clearsCaptureHealth: false
        )
    }

    static let savingRecording = busy(
        stateTitle: L10n.text("saving recording…"),
        toggleTitle: L10n.text("Saving recording…")
    )

    static func pausedScreenRecording(elapsed: String) -> Self {
        RecordingMenuPresentation(
            stateTitle: L10n.format("paused screen recording · %@", elapsed),
            toggleTitle: L10n.text("Stop recording"),
            pauseResumeTitle: L10n.text("Resume screen recording"),
            toggleEnabled: true,
            pauseResumeVisible: true,
            pauseResumeEnabled: true,
            audioOnlyEnabled: false,
            screenSourceEnabled: false,
            exportFolderEnabled: false,
            capturePrivacyEnabled: false,
            recordingIndicatorActive: false,
            clearsCaptureHealth: false
        )
    }

    static func rotatingScreenRecording(resuming: Bool) -> Self {
        RecordingMenuPresentation(
            stateTitle: resuming
                ? L10n.text("resuming screen recording…")
                : L10n.text("pausing screen recording…"),
            toggleTitle: L10n.text("Stop recording"),
            pauseResumeTitle: resuming
                ? L10n.text("Resuming screen recording…")
                : L10n.text("Pausing screen recording…"),
            toggleEnabled: false,
            pauseResumeVisible: true,
            pauseResumeEnabled: false,
            audioOnlyEnabled: false,
            screenSourceEnabled: false,
            exportFolderEnabled: false,
            capturePrivacyEnabled: false,
            recordingIndicatorActive: !resuming,
            clearsCaptureHealth: false
        )
    }

    private static func busy(
        stateTitle: String,
        toggleTitle: String,
        clearsCaptureHealth: Bool = false
    ) -> Self {
        RecordingMenuPresentation(
            stateTitle: stateTitle,
            toggleTitle: toggleTitle,
            pauseResumeTitle: L10n.text("Pause screen recording"),
            toggleEnabled: false,
            pauseResumeVisible: false,
            pauseResumeEnabled: false,
            audioOnlyEnabled: false,
            screenSourceEnabled: false,
            exportFolderEnabled: false,
            capturePrivacyEnabled: false,
            recordingIndicatorActive: false,
            clearsCaptureHealth: clearsCaptureHealth
        )
    }
}
