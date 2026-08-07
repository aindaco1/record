import Foundation
@testable import Record
import XCTest

@MainActor
final class RecordingNamePreferencesTests: XCTestCase {
    func testDefaultsToEnabledSafeTemplate() throws {
        let defaults = try makeDefaults()
        let preferences = RecordingNamePreferences(defaults: defaults)
        XCTAssertTrue(preferences.isEnabled)
        XCTAssertEqual(preferences.template.rawValue, "{date} at {time} - {color} {animal}")
    }

    func testInvalidStoredTemplateFailsClosedToDefault() throws {
        let defaults = try makeDefaults()
        defaults.set("{unknown}", forKey: RecordingNamePreferences.templateKey)
        let preferences = RecordingNamePreferences(defaults: defaults)
        XCTAssertEqual(preferences.template, .defaultValue)
    }

    func testClipboardAutoclosureIsLazy() throws {
        let defaults = try makeDefaults()
        let preferences = RecordingNamePreferences(defaults: defaults)
        try preferences.setTemplate("{date}")
        var reads = 0
        func readClipboard() -> String? {
            reads += 1
            return "private"
        }
        _ = preferences.renderName(at: Date(), clipboard: readClipboard())
        XCTAssertEqual(reads, 0)

        try preferences.setTemplate("{clipboard}")
        _ = preferences.renderName(at: Date(), clipboard: readClipboard())
        XCTAssertEqual(reads, 1)
    }

    private func makeDefaults() throws -> UserDefaults {
        let suite = "com.aindaco.record.name-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suite)
        }
        return defaults
    }
}
