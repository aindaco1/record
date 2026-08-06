import Foundation
@testable import Record
import RecordCore
import XCTest

@MainActor
final class CapturePrivacyPreferencesTests: XCTestCase {
    func testEveryPrivacyFeatureDefaultsOn() throws {
        let preferences = CapturePrivacyPreferences(defaults: try makeDefaults())
        XCTAssertEqual(preferences.configuration, CapturePrivacyConfiguration())
    }

    func testFeaturesToggleIndependentlyAndPersist() throws {
        let defaults = try makeDefaults()
        let preferences = CapturePrivacyPreferences(defaults: defaults)

        preferences.toggle(.notifications)
        preferences.toggle(.desktopItems)

        let restored = CapturePrivacyPreferences(defaults: defaults).configuration
        XCTAssertFalse(restored.hideNotifications)
        XCTAssertTrue(restored.hideMenuBar)
        XCTAssertFalse(restored.hideDesktopItems)
    }

    private func makeDefaults() throws -> UserDefaults {
        let suite = "com.aindaco.record.privacy-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suite)
        }
        return defaults
    }
}
