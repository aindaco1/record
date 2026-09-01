@testable import Record
import AppKit
import RecordCore
import XCTest

@MainActor
final class ScreenshotShortcutRecorderTests: XCTestCase {
    func testRecorderMapsOnlySupportedShortcutModifiers() {
        let modifiers = ShortcutRecorderButton.shortcutModifiers(
            from: [.command, .shift, .capsLock, .function]
        )

        XCTAssertEqual(modifiers, [.command, .shift])
    }

    func testRecorderAllowsAnySingleSupportedModifier() {
        XCTAssertEqual(
            ShortcutRecorderButton.shortcutModifiers(from: [.option]),
            [.option]
        )
    }
}
