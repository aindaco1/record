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

    func testNewKapMenuBarImageIsAProperlySizedTemplate() throws {
        let image = try XCTUnwrap(MenuBarController.menuBarImage())

        XCTAssertTrue(image.isTemplate)
        XCTAssertEqual(image.size.width, 16)
        XCTAssertEqual(image.size.height, 16)
    }

    func testRecordingImageIsWhitePresentationRatherThanAdaptiveTemplate() throws {
        let image = try XCTUnwrap(MenuBarController.recordingMenuBarImage())

        XCTAssertFalse(image.isTemplate)
        XCTAssertEqual(image.size.width, 16)
        XCTAssertEqual(image.size.height, 16)

        let data = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: data))
        let visibleColors = (0..<bitmap.pixelsHigh).flatMap { y in
            (0..<bitmap.pixelsWide).compactMap { x in
                bitmap.colorAt(x: x, y: y)
            }
        }.filter { $0.alphaComponent > 0.05 }
        XCTAssertFalse(visibleColors.isEmpty)
        for color in visibleColors {
            let rgb = try XCTUnwrap(color.usingColorSpace(.sRGB))
            XCTAssertGreaterThan(rgb.redComponent, 0.95)
            XCTAssertGreaterThan(rgb.greenComponent, 0.95)
            XCTAssertGreaterThan(rgb.blueComponent, 0.95)
        }
    }

    func testRecordingPulseIsBoundedAndRepeating() {
        let animation = MenuBarController.recordingPulseAnimation()

        XCTAssertEqual(animation.keyPath, "opacity")
        XCTAssertEqual(animation.fromValue as? Double, 1)
        XCTAssertEqual(animation.toValue as? Double, 0.35)
        XCTAssertEqual(animation.duration, 0.65)
        XCTAssertTrue(animation.autoreverses)
        XCTAssertEqual(animation.repeatCount, .infinity)
    }

    func testScreenshotFlashImageIsAProperlySizedTemplate() throws {
        let image = try XCTUnwrap(MenuBarController.screenshotFlashImage())

        XCTAssertTrue(image.isTemplate)
        XCTAssertEqual(image.size, NSSize(width: 16, height: 16))
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
