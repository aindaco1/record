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
        stateTitle: "idle",
        toggleTitle: "Start screen recording",
        pauseResumeTitle: "Pause screen recording",
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
            stateTitle: "● \(mode.displayName) recording · \(elapsed)\(health)",
            toggleTitle: "Stop recording",
            pauseResumeTitle: "Pause screen recording",
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
            stateTitle: "waiting for \(mode.displayName) recording permissions…",
            toggleTitle: "Start screen recording",
            clearsCaptureHealth: true
        )
    }

    static let preparingScreenRecording = busy(
        stateTitle: "preparing screen recording…",
        toggleTitle: "Preparing screen recording…",
        clearsCaptureHealth: true
    )

    static func stoppingScreenRecording(
        captureStarted: Bool,
        indicatorActive: Bool
    ) -> Self {
        RecordingMenuPresentation(
            stateTitle: "stopping recording…",
            toggleTitle: "Stopping recording…",
            pauseResumeTitle: "Pause screen recording",
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
        stateTitle: "saving recording…",
        toggleTitle: "Saving recording…"
    )

    static func pausedScreenRecording(elapsed: String) -> Self {
        RecordingMenuPresentation(
            stateTitle: "paused screen recording · \(elapsed)",
            toggleTitle: "Stop recording",
            pauseResumeTitle: "Resume screen recording",
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
                ? "resuming screen recording…"
                : "pausing screen recording…",
            toggleTitle: "Stop recording",
            pauseResumeTitle: resuming
                ? "Resuming screen recording…"
                : "Pausing screen recording…",
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
            pauseResumeTitle: "Pause screen recording",
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
