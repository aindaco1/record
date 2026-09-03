@testable import Record
import XCTest

@MainActor
final class MenuBarControllerTests: XCTestCase {
    func testMenuUsesStableActionLabels() {
        XCTAssertEqual(MenuBarController.settingsMenuTitle, "Settings…")
        XCTAssertEqual(
            MenuBarController.openRecoveryFolderMenuTitle,
            "Open Recovery Folder…"
        )
        XCTAssertEqual(MenuBarController.openLastRecordingMenuTitle, "Open last recording")
        XCTAssertEqual(MenuBarController.checkForUpdatesMenuTitle, "Check for Updates…")
        XCTAssertEqual(MenuBarController.screenSourceMenuTitle, "Screen source")
        XCTAssertEqual(MenuBarController.captureDisplayMenuTitle, "Capture Full Display")
        XCTAssertEqual(
            MenuBarController.captureWindowMenuTitle,
            "Capture Window or Application…"
        )
        XCTAssertEqual(MenuBarController.captureAreaMenuTitle, "Capture Area…")
    }

    func testMenuKeepsActionsAndMovesPersistentPreferencesIntoSettings() throws {
        let menu = MenuBarController()

        for movedTitle in [
            "Plugins",
            "Transcript model",
            "Select export folder…",
            "Open at Login",
            "Screenshot Settings…",
        ] {
            XCTAssertFalse(menu.topLevelMenuTitles.contains(movedTitle), movedTitle)
        }

        let settingsIndex = try XCTUnwrap(
            menu.topLevelMenuLayout.firstIndex(of: MenuBarController.settingsMenuTitle)
        )
        XCTAssertEqual(menu.topLevelMenuLayout[settingsIndex - 1], "|")
        XCTAssertEqual(menu.topLevelMenuLayout[settingsIndex + 1], "|")
        XCTAssertEqual(
            menu.topLevelMenuLayout[settingsIndex + 2],
            MenuBarController.checkForUpdatesMenuTitle
        )
    }

    func testScreenSourceMenuHasExactlyOnePersistentModeSelected() {
        let menu = MenuBarController()

        menu.updateScreenCaptureSource(.mainDisplay)
        XCTAssertEqual(menu.selectedScreenSource, .mainDisplay)
        menu.updateScreenCaptureSource(.systemPicker)
        XCTAssertEqual(menu.selectedScreenSource, .systemPicker)
        menu.updateScreenCaptureSource(.region)
        XCTAssertEqual(menu.selectedScreenSource, .region)
    }

    func testRetryTranscriptionAppearsOnlyForAnActionableFailure() {
        let menu = MenuBarController()

        menu.updateTranscription("transcribing")
        XCTAssertFalse(menu.isRetryTranscriptionMenuItemVisible)

        menu.updateTranscription("transcription failed", retryAvailable: true)
        XCTAssertTrue(menu.isRetryTranscriptionMenuItemVisible)

        menu.updateTranscription(nil)
        XCTAssertFalse(menu.isRetryTranscriptionMenuItemVisible)
    }

    func testLastRecordingStartsDisabledAndBecomesActionable() {
        let menu = MenuBarController()

        XCTAssertFalse(menu.isOpenLastRecordingEnabled)
        menu.updateLastRecording(available: true)
        XCTAssertTrue(menu.isOpenLastRecordingEnabled)
        menu.updateLastRecording(available: false)
        XCTAssertFalse(menu.isOpenLastRecordingEnabled)
    }

    func testRecoveryFolderAppearsOnlyWhenMaterialExists() {
        let menu = MenuBarController()

        XCTAssertFalse(menu.isRecoveryFolderMenuItemVisible)
        menu.updateRecoveryMaterial(available: true)
        XCTAssertTrue(menu.isRecoveryFolderMenuItemVisible)
        menu.updateRecoveryMaterial(available: false)
        XCTAssertFalse(menu.isRecoveryFolderMenuItemVisible)
    }

    func testCameraMenuBarImageIsWideRetinaTemplateWithTransparentBackground() throws {
        let image = try XCTUnwrap(MenuBarController.menuBarImage())

        XCTAssertTrue(image.isTemplate)
        XCTAssertEqual(image.size, NSSize(width: 24, height: 18))
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)))
        XCTAssertEqual(bitmap.pixelsWide, 48)
        XCTAssertEqual(bitmap.pixelsHigh, 36)
        XCTAssertEqual(bitmap.colorAt(x: 0, y: 0)?.alphaComponent, 0)
        XCTAssertGreaterThan(bitmap.colorAt(x: 16, y: 15)?.alphaComponent ?? 0, 0.9)
    }

    func testRecordingDotIsRedLargeEnoughAndInsetOverTheLowerRightCameraBody() throws {
        let indicator = MenuBarRecordingIndicatorView()
        indicator.layoutSubtreeIfNeeded()
        indicator.layout()
        XCTAssertEqual(indicator.dotLayer.frame, CGRect(x: 12, y: 1, width: 6, height: 6))
        XCTAssertTrue(indicator.bounds.contains(indicator.dotLayer.frame))
        let color = try XCTUnwrap(
            NSColor(cgColor: try XCTUnwrap(indicator.dotLayer.fillColor))?.usingColorSpace(.sRGB))
        XCTAssertGreaterThan(color.redComponent, 0.8)
        XCTAssertLessThan(color.greenComponent, 0.5)
        XCTAssertLessThan(color.blueComponent, 0.5)
        XCTAssertNil(indicator.hitTest(NSPoint(x: 15, y: 4)))
    }

    func testOnlyDotAnimatesWithoutRestartingOnElapsedUpdates() throws {
        let menu = MenuBarController()
        let indicator = menu.recordingIndicator
        indicator.update(recording: true, reduceMotion: false)
        let key = MenuBarController.recordingPulseAnimationKey
        let first = try XCTUnwrap(indicator.dotLayer.animation(forKey: key))
        indicator.update(recording: true, reduceMotion: false)
        XCTAssertEqual(indicator.dotLayer.animation(forKey: key)?.beginTime, first.beginTime)
        XCTAssertNil(indicator.layer?.animation(forKey: key))
        XCTAssertNil(indicator.superview?.layer?.animation(forKey: key))
        XCTAssertFalse(indicator.isHidden)
    }

    func testReduceMotionUsesSteadyDotAndCanChangeDuringRecording() {
        let indicator = MenuBarRecordingIndicatorView()
        let key = MenuBarController.recordingPulseAnimationKey
        indicator.update(recording: true, reduceMotion: false)
        XCTAssertNotNil(indicator.dotLayer.animation(forKey: key))
        indicator.update(recording: true, reduceMotion: true)
        XCTAssertFalse(indicator.isHidden)
        XCTAssertNil(indicator.dotLayer.animation(forKey: key))
        XCTAssertEqual(indicator.dotLayer.opacity, 1)
        indicator.update(recording: true, reduceMotion: false)
        XCTAssertNotNil(indicator.dotLayer.animation(forKey: key))
    }

    func testRecordingDotFollowsScreenAudioPauseResumeAndStopStates() {
        let menu = MenuBarController()
        XCTAssertTrue(menu.recordingIndicator.isHidden)
        for mode in [RecordingMode.screen, .audioOnly] {
            menu.update(recording: true, elapsed: "0:01", mode: mode)
            XCTAssertFalse(menu.recordingIndicator.isHidden)
            menu.update(recording: true, elapsed: "0:02", mode: mode)
            XCTAssertFalse(menu.recordingIndicator.isHidden)
            menu.updateSavingRecording()
            XCTAssertTrue(menu.recordingIndicator.isHidden)
            XCTAssertNil(
                menu.recordingIndicator.dotLayer.animation(
                    forKey: MenuBarController.recordingPulseAnimationKey))
        }
        menu.update(recording: true, elapsed: "0:03")
        menu.updatePausedScreenRecording(elapsed: "0:03")
        XCTAssertTrue(menu.recordingIndicator.isHidden)
        menu.updateRotatingScreenRecording(resuming: true)
        XCTAssertTrue(menu.recordingIndicator.isHidden)
        menu.update(recording: true, elapsed: "0:04")
        XCTAssertFalse(menu.recordingIndicator.isHidden)
        menu.updateStoppingScreenRecording(captureStarted: true, indicatorActive: true)
        XCTAssertFalse(menu.recordingIndicator.isHidden)
        menu.update(recording: false, elapsed: nil)
        XCTAssertTrue(menu.recordingIndicator.isHidden)
    }

    func testScreenshotFeedbackKeepsTheRecordingDotAndRestoresTemplateCamera() async throws {
        let menu = MenuBarController()
        menu.update(recording: true, elapsed: "0:01")
        let button = try XCTUnwrap(menu.recordingIndicator.superview as? NSButton)
        let pulseStart = menu.recordingIndicator.dotLayer.animation(
            forKey: MenuBarController.recordingPulseAnimationKey)?.beginTime
        menu.flashScreenshotSuccess(duration: 0)
        XCTAssertFalse(menu.recordingIndicator.isHidden)
        let restored = expectation(description: "screenshot feedback restored")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { restored.fulfill() }
        await fulfillment(of: [restored], timeout: 1)
        XCTAssertTrue(try XCTUnwrap(button.image).isTemplate)
        XCTAssertEqual(button.image?.size, MenuBarController.menuBarImageSize)
        XCTAssertFalse(menu.recordingIndicator.isHidden)
        XCTAssertEqual(
            menu.recordingIndicator.dotLayer.animation(
                forKey: MenuBarController.recordingPulseAnimationKey)?.beginTime, pulseStart)
    }

    func testRecordingPulseIsBoundedAndRepeating() {
        let animation = MenuBarController.recordingPulseAnimation()

        XCTAssertEqual(animation.keyPath, "opacity")
        XCTAssertEqual(animation.fromValue as? Double, 1)
        XCTAssertEqual(animation.toValue as? Double, 0.1)
        XCTAssertEqual(animation.duration, 0.65)
        XCTAssertTrue(animation.autoreverses)
        XCTAssertEqual(animation.repeatCount, .infinity)
    }

    func testScreenshotFlashImageIsAProperlySizedTemplate() throws {
        let image = try XCTUnwrap(MenuBarController.screenshotFlashImage())

        XCTAssertTrue(image.isTemplate)
        XCTAssertEqual(image.size, MenuBarController.menuBarImageSize)
    }

    func testScreenshotCaptureLocksOnlySharedDestinationAndRestoresRecordingPolicy() {
        let menu = MenuBarController()

        XCTAssertTrue(menu.areScreenshotCaptureItemsEnabled)
        XCTAssertTrue(menu.settingsInteractionAvailability.destinationSelectionEnabled)
        menu.updateScreenshotCaptureAvailable(false)
        XCTAssertFalse(menu.areScreenshotCaptureItemsEnabled)
        XCTAssertFalse(menu.settingsInteractionAvailability.destinationSelectionEnabled)

        menu.update(recording: true, elapsed: "0:01", mode: .screen)
        menu.updateScreenshotCaptureAvailable(true)
        XCTAssertTrue(menu.areScreenshotCaptureItemsEnabled)
        XCTAssertFalse(menu.settingsInteractionAvailability.destinationSelectionEnabled)
        XCTAssertFalse(menu.settingsInteractionAvailability.capturePrivacyEnabled)

        menu.update(recording: false, elapsed: nil)
        XCTAssertEqual(menu.settingsInteractionAvailability, .idle)
    }

    func testSettingsReceivesRecordingAvailabilityChanges() {
        let menu = MenuBarController()
        var received: [SettingsInteractionAvailability] = []
        menu.onSettingsInteractionAvailabilityChanged = { received.append($0) }

        menu.update(recording: true, elapsed: "0:01", mode: .screen)
        XCTAssertEqual(
            received.last,
            SettingsInteractionAvailability(
                destinationSelectionEnabled: false,
                capturePrivacyEnabled: false
            )
        )

        menu.update(recording: false, elapsed: nil)
        XCTAssertEqual(received.last, .idle)
    }

    func testPauseControlIsScopedToScreenRecordingAndRepresentsTransitions() {
        let menu = MenuBarController()

        menu.update(recording: true, elapsed: "0:03", mode: .audioOnly)
        XCTAssertFalse(menu.isPauseResumeVisible)

        menu.update(recording: true, elapsed: "0:03", mode: .screen)
        XCTAssertTrue(menu.isPauseResumeVisible)
        XCTAssertTrue(menu.isPauseResumeEnabled)
        XCTAssertEqual(menu.pauseResumeTitle, "Pause screen recording")

        menu.updateRotatingScreenRecording(resuming: false)
        XCTAssertFalse(menu.isPauseResumeEnabled)
        XCTAssertEqual(menu.pauseResumeTitle, "Pausing screen recording…")

        menu.updatePausedScreenRecording(elapsed: "0:03")
        XCTAssertTrue(menu.isPauseResumeEnabled)
        XCTAssertEqual(menu.pauseResumeTitle, "Resume screen recording")

        menu.update(recording: false, elapsed: nil)
        XCTAssertFalse(menu.isPauseResumeVisible)
    }
}
