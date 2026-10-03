import Foundation
@testable import Record
import RecordCore
import XCTest

final class RecordingShortcutsTests: XCTestCase {
    func testOffPersistsAndPhysicalKeysCannotDuplicateAnotherAction() throws {
        let domain = "record-shortcuts-test-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let preferences = RecordingShortcuts(defaults: defaults)
        XCTAssertNil(preferences[.screen])
        let screenshot = try XCTUnwrap(ScreenshotShortcutSet.defaults.area)
        let renamedKey = try ScreenshotShortcut(
            keyCode: screenshot.keyCode, modifiers: screenshot.modifiers, keyLabel: "Other")
        XCTAssertThrowsError(try preferences.set(renamedKey, for: .screen, screenshots: .defaults))
        let shortcut = try ScreenshotShortcut(
            keyCode: 15, modifiers: [.command, .option], keyLabel: "R")
        try preferences.set(shortcut, for: .screen, screenshots: .defaults)
        XCTAssertEqual(preferences[.screen], shortcut)
        XCTAssertThrowsError(try preferences.set(shortcut, for: .audio, screenshots: .defaults))
        try preferences.set(nil, for: .screen, screenshots: .defaults)
        XCTAssertNil(RecordingShortcuts(defaults: defaults)[.screen])
    }
}
