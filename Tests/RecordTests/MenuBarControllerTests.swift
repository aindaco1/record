@testable import Record
import XCTest

@MainActor
final class MenuBarControllerTests: XCTestCase {
    func testMenuUsesStableActionLabels() {
        XCTAssertEqual(MenuBarController.transcriptionModelMenuTitle, "Transcript model")
        XCTAssertEqual(MenuBarController.exportFolderMenuTitle, "Select export folder…")
        XCTAssertEqual(MenuBarController.openTempSessionMenuTitle, "Open temp session")
        XCTAssertEqual(MenuBarController.openLastRecordingMenuTitle, "Open last recording")
        XCTAssertEqual(MenuBarController.checkForUpdatesMenuTitle, "Check for Updates…")
        XCTAssertEqual(MenuBarController.launchAtLoginMenuTitle, "Open at Login")
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

    func testMacWhisperIsAbsentUnlessTheIntegrationIsAvailable() {
        let menu = MenuBarController()

        menu.updateTranscriptionEngine(
            .parakeet,
            macWhisperAvailable: false,
            parakeetModelAvailable: true
        )
        XCTAssertFalse(menu.isMacWhisperMenuItemVisible)

        menu.updateTranscriptionEngine(
            .parakeet,
            macWhisperAvailable: true,
            parakeetModelAvailable: true
        )
        XCTAssertTrue(menu.isMacWhisperMenuItemVisible)
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
}
