import Foundation
import RecordCore
@testable import Record
import XCTest

@MainActor
final class ScreenshotPreferencesTests: XCTestCase {
    func testDefaultsToLosslessPNGHighQualityJPEGSoundAndRequestedShortcuts() throws {
        let defaults = try makeDefaults()
        let preferences = ScreenshotPreferences(defaults: defaults)

        XCTAssertEqual(preferences.format, .png)
        XCTAssertEqual(preferences.jpegQuality, 0.95)
        XCTAssertTrue(preferences.playShutterSound)
        XCTAssertEqual(preferences.shortcuts, .defaults)
    }

    func testPersistsFormatQualitySoundAndAnExplicitlyDisabledShortcut() throws {
        let defaults = try makeDefaults()
        let preferences = ScreenshotPreferences(defaults: defaults)

        preferences.format = .jpeg
        preferences.jpegQuality = 2
        preferences.playShutterSound = false
        try preferences.setShortcut(nil, for: .area)

        let restored = ScreenshotPreferences(defaults: defaults)
        XCTAssertEqual(restored.format, .jpeg)
        XCTAssertEqual(restored.jpegQuality, 1)
        XCTAssertFalse(restored.playShutterSound)
        XCTAssertNil(restored.shortcuts.area)
        XCTAssertEqual(restored.shortcuts.display, ScreenshotShortcutSet.defaults.display)
    }

    func testRejectsDuplicateShortcutWithoutChangingPreferences() throws {
        let defaults = try makeDefaults()
        let preferences = ScreenshotPreferences(defaults: defaults)

        XCTAssertThrowsError(
            try preferences.setShortcut(preferences.shortcuts.display, for: .area)
        )
        XCTAssertEqual(preferences.shortcuts, .defaults)
    }

    private func makeDefaults() throws -> UserDefaults {
        let suite = "ScreenshotPreferencesTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }
}
