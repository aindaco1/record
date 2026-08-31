@testable import Record
import XCTest

final class RecordingMenuPresentationTests: XCTestCase {
    func testIdleAndRecordingOwnTheCompleteControlState() {
        XCTAssertEqual(RecordingMenuPresentation.idle.stateTitle, "idle")
        XCTAssertTrue(RecordingMenuPresentation.idle.toggleEnabled)
        XCTAssertTrue(RecordingMenuPresentation.idle.audioOnlyEnabled)
        XCTAssertTrue(RecordingMenuPresentation.idle.screenSourceEnabled)
        XCTAssertTrue(RecordingMenuPresentation.idle.exportFolderEnabled)
        XCTAssertTrue(RecordingMenuPresentation.idle.capturePrivacyEnabled)
        XCTAssertFalse(RecordingMenuPresentation.idle.recordingIndicatorActive)

        let screen = RecordingMenuPresentation.recording(
            mode: .screen,
            elapsed: "0:12",
            healthNote: "capture under load"
        )
        XCTAssertEqual(
            screen.stateTitle,
            "● screen recording · 0:12 · capture under load"
        )
        XCTAssertTrue(screen.toggleEnabled)
        XCTAssertTrue(screen.pauseResumeVisible)
        XCTAssertTrue(screen.pauseResumeEnabled)
        XCTAssertTrue(screen.recordingIndicatorActive)
        assertConfigurationIsLocked(screen)

        let audio = RecordingMenuPresentation.recording(
            mode: .audioOnly,
            elapsed: "0:03",
            healthNote: nil
        )
        XCTAssertFalse(audio.pauseResumeVisible)
        XCTAssertFalse(audio.pauseResumeEnabled)
        assertConfigurationIsLocked(audio)
    }

    func testEveryBusyPhaseLocksConflictingConfiguration() {
        let phases: [RecordingMenuPresentation] = [
            .requestingPermissions(for: .screen),
            .preparingScreenRecording,
            .savingRecording,
            .stoppingScreenRecording(captureStarted: true, indicatorActive: true),
            .rotatingScreenRecording(resuming: false),
            .rotatingScreenRecording(resuming: true),
        ]

        for phase in phases {
            XCTAssertFalse(phase.audioOnlyEnabled, phase.stateTitle)
            assertConfigurationIsLocked(phase)
        }
    }

    func testPauseResumeAndStoppingIndicatorsReflectCaptureActivity() {
        let paused = RecordingMenuPresentation.pausedScreenRecording(elapsed: "1:23")
        XCTAssertTrue(paused.toggleEnabled)
        XCTAssertTrue(paused.pauseResumeVisible)
        XCTAssertTrue(paused.pauseResumeEnabled)
        XCTAssertFalse(paused.recordingIndicatorActive)

        let pausing = RecordingMenuPresentation.rotatingScreenRecording(resuming: false)
        XCTAssertTrue(pausing.recordingIndicatorActive)
        XCTAssertFalse(pausing.pauseResumeEnabled)

        let resuming = RecordingMenuPresentation.rotatingScreenRecording(resuming: true)
        XCTAssertFalse(resuming.recordingIndicatorActive)
        XCTAssertFalse(resuming.pauseResumeEnabled)

        let stoppingBeforeCapture = RecordingMenuPresentation.stoppingScreenRecording(
            captureStarted: false,
            indicatorActive: false
        )
        XCTAssertFalse(stoppingBeforeCapture.pauseResumeVisible)
        XCTAssertFalse(stoppingBeforeCapture.recordingIndicatorActive)
    }

    private func assertConfigurationIsLocked(
        _ presentation: RecordingMenuPresentation,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertFalse(presentation.screenSourceEnabled, file: file, line: line)
        XCTAssertFalse(presentation.exportFolderEnabled, file: file, line: line)
        XCTAssertFalse(presentation.capturePrivacyEnabled, file: file, line: line)
    }
}
