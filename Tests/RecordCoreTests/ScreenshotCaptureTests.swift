import Foundation
import RecordCore
import XCTest

final class ScreenshotCaptureTests: XCTestCase {
    func testOnlyDirectDisplayModesRequireBroadScreenCaptureAccess() {
        XCTAssertTrue(ScreenshotCaptureKind.display.requiresDirectScreenCaptureAccess)
        XCTAssertFalse(
            ScreenshotCaptureKind.windowOrApplication.requiresDirectScreenCaptureAccess
        )
        XCTAssertTrue(ScreenshotCaptureKind.area.requiresDirectScreenCaptureAccess)
    }

    func testStillPixelSizePreservesNativeFiveKDimensions() throws {
        XCTAssertEqual(
            try ScreenshotPixelSize(width: 5_120, height: 2_880),
            try ScreenshotPixelSize(width: 5_120, height: 2_880)
        )
        XCTAssertThrowsError(try ScreenshotPixelSize(width: 0, height: 1))
    }

    func testDefaultShortcutsMatchTheRecordOneThreeContract() {
        let shortcuts = ScreenshotShortcutSet.defaults

        XCTAssertEqual(shortcuts[.display]?.displayString, "⇧⌘1")
        XCTAssertEqual(shortcuts[.windowOrApplication]?.displayString, "⇧⌘2")
        XCTAssertEqual(shortcuts[.area]?.displayString, "⇧⌘4")
    }

    func testShortcutsRequireAModifierAndRejectDuplicates() throws {
        XCTAssertThrowsError(
            try ScreenshotShortcut(keyCode: 18, modifiers: [], keyLabel: "1")
        )

        let shortcut = try ScreenshotShortcut(
            keyCode: 18,
            modifiers: [.command],
            keyLabel: "1"
        )
        XCTAssertThrowsError(
            try ScreenshotShortcutSet(
                display: shortcut,
                windowOrApplication: shortcut,
                area: nil
            )
        ) { error in
            XCTAssertEqual(
                error as? ScreenshotCaptureContractError,
                .duplicateShortcut
            )
        }
    }

    func testFilenameUsesLocalTimestampAndCollisionSuffixes() {
        let zone = TimeZone(secondsFromGMT: 0)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let date = calendar.date(
            from: DateComponents(
                year: 2026,
                month: 9,
                day: 1,
                hour: 14,
                minute: 32,
                second: 8
            )
        )!
        let directory = URL(fileURLWithPath: "/tmp/screenshots", isDirectory: true)
        let first = directory.appendingPathComponent(
            "Screenshot 2026-09-01 at 14.32.08.png"
        )

        XCTAssertEqual(
            ScreenshotFileNamePolicy.baseName(
                at: date,
                calendar: calendar,
                timeZone: zone
            ),
            "Screenshot 2026-09-01 at 14.32.08"
        )
        XCTAssertEqual(
            ScreenshotFileNamePolicy.nextAvailableURL(
                in: directory,
                at: date,
                format: .png,
                calendar: calendar,
                timeZone: zone,
                fileExists: { $0 == first }
            ).lastPathComponent,
            "Screenshot 2026-09-01 at 14.32.08-2.png"
        )
    }

    func testShutterFeedbackIsSuppressedDuringEveryRecording() {
        XCTAssertTrue(
            ScreenshotFeedbackPolicy.shouldPlayShutter(
                preferenceEnabled: true,
                recordingIsActive: false
            )
        )
        XCTAssertFalse(
            ScreenshotFeedbackPolicy.shouldPlayShutter(
                preferenceEnabled: true,
                recordingIsActive: true
            )
        )
        XCTAssertFalse(
            ScreenshotFeedbackPolicy.shouldPlayShutter(
                preferenceEnabled: false,
                recordingIsActive: false
            )
        )
    }
}
