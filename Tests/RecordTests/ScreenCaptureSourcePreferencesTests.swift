import Foundation
@testable import Record
import XCTest

final class ScreenCaptureSourcePreferencesTests: XCTestCase {
    func testDefaultsToMainDisplayAndPersistsOnlyTheMode() throws {
        let suiteName = "ScreenCaptureSourcePreferencesTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let key = "source"
        let preferences = ScreenCaptureSourcePreferences(defaults: defaults, key: key)

        XCTAssertEqual(preferences.selected, .mainDisplay)
        preferences.selected = .systemPicker
        XCTAssertEqual(preferences.selected, .systemPicker)
        XCTAssertEqual(defaults.dictionaryRepresentation()[key] as? String, "systemPicker")
        XCTAssertEqual(defaults.dictionaryRepresentation().keys.filter { $0 == key }, [key])
    }

    func testUnknownPersistedModeFailsClosedToMainDisplay() throws {
        let suiteName = "ScreenCaptureSourcePreferencesTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("future-mode", forKey: "source")

        XCTAssertEqual(
            ScreenCaptureSourcePreferences(defaults: defaults, key: "source").selected,
            .mainDisplay
        )
    }
}
