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

    func testFreshInstallSeedsNewDefaultsBeforeStartupCreatesStorage() throws {
        let (defaults, suite, home) = try makeLaunchFixture()
        let root = RecordPaths.defaultRecordingsDirectory(home: home)
        let preferences = ScreenshotPreferences(defaults: defaults)
        preferences.prepareForLaunch(recordingsRoot: root, home: home, preferencesDomainName: suite)
        XCTAssertEqual(preferences.shortcuts, .defaults)
        XCTAssertEqual(
            defaults.integer(forKey: ScreenshotPreferences.shortcutDefaultsVersionKey), 2)

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let relaunched = ScreenshotPreferences(defaults: defaults)
        relaunched.prepareForLaunch(recordingsRoot: root, home: home, preferencesDomainName: suite)
        XCTAssertEqual(relaunched.shortcuts, .defaults)
    }

    func testUntouchedUpgradeKeepsOldDefaultsWithoutSavedPreferences() throws {
        let (defaults, suite, home) = try makeLaunchFixture()
        let root = RecordPaths.defaultRecordingsDirectory(home: home)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let preferences = ScreenshotPreferences(defaults: defaults)
        preferences.prepareForLaunch(recordingsRoot: root, home: home, preferencesDomainName: suite)
        XCTAssertEqual(preferences.shortcuts, .legacyDefaults)
        XCTAssertEqual(
            defaults.integer(forKey: ScreenshotPreferences.shortcutDefaultsVersionKey), 1)

        try FileManager.default.removeItem(at: root)
        let relaunched = ScreenshotPreferences(defaults: defaults)
        relaunched.prepareForLaunch(recordingsRoot: root, home: home, preferencesDomainName: suite)
        XCTAssertEqual(relaunched.shortcuts, .legacyDefaults)
    }

    func testOtherPreferencesOrConfigurationPreserveUntouchedUpgradeDefaults() throws {
        for evidence in ["preference", "configuration", "defaultRoot", "customRoot"] {
            let (defaults, suite, home) = try makeLaunchFixture()
            let root = home.appendingPathComponent("CustomRecordings")
            switch evidence {
            case "preference":
                defaults.set(false, forKey: ScreenshotPreferences.shutterSoundKey)
            case "configuration":
                let configuration = RecordPaths.configurationFile(home: home)
                try FileManager.default.createDirectory(
                    at: configuration.deletingLastPathComponent(), withIntermediateDirectories: true
                )
                try Data("{}".utf8).write(to: configuration)
            default:
                let existingRoot =
                    evidence == "defaultRoot"
                    ? RecordPaths.defaultRecordingsDirectory(home: home) : root
                try FileManager.default.createDirectory(
                    at: existingRoot, withIntermediateDirectories: true
                )
            }
            let preferences = ScreenshotPreferences(defaults: defaults)
            preferences.prepareForLaunch(
                recordingsRoot: root, home: home, preferencesDomainName: suite)
            XCTAssertEqual(preferences.shortcuts, .legacyDefaults, evidence)
        }
    }

    func testUpgradePreservesSavedLegacyCustomAndOffBindingsExactly() throws {
        for area in [
            ScreenshotShortcutSet.legacyDefaults.area, ScreenshotShortcutSet.defaults.area, nil,
        ] {
            let (defaults, suite, home) = try makeLaunchFixture()
            let preferences = ScreenshotPreferences(defaults: defaults)
            let customDisplay = try ScreenshotShortcut(
                keyCode: 0, modifiers: [.control, .option], keyLabel: "A")
            let saved = try ScreenshotShortcutSet(
                display: customDisplay, windowOrApplication: nil, area: area
            )
            preferences.shortcuts = saved
            let stored = try XCTUnwrap(defaults.persistentDomain(forName: suite))
            preferences.prepareForLaunch(
                recordingsRoot: home.appendingPathComponent("Recordings"), home: home,
                preferencesDomainName: suite
            )
            XCTAssertEqual(preferences.shortcuts, saved)
            for (key, value) in stored {
                XCTAssertEqual(defaults.object(forKey: key) as? NSObject, value as? NSObject, key)
            }
        }
    }

    func testPartialLegacyPreferencesDoNotAcquireNewConflictsOrResetOtherBindings() throws {
        let (defaults, suite, home) = try makeLaunchFixture()
        // A pre-1.4 user assigned the proposed new Area binding to Display.
        // Area itself is still unsaved and must retain the old default.
        defaults.set(true, forKey: "screenshots.shortcut.display.enabled")
        defaults.set(21, forKey: "screenshots.shortcut.display.keyCode")
        defaults.set(7, forKey: "screenshots.shortcut.display.modifiers")
        defaults.set("4", forKey: "screenshots.shortcut.display.keyLabel")
        let preferences = ScreenshotPreferences(defaults: defaults)
        preferences.prepareForLaunch(
            recordingsRoot: home.appendingPathComponent("Recordings"), home: home,
            preferencesDomainName: suite
        )
        XCTAssertEqual(preferences.shortcuts.display, ScreenshotShortcutSet.defaults.area)
        XCTAssertEqual(preferences.shortcuts.area, ScreenshotShortcutSet.legacyDefaults.area)
        XCTAssertEqual(
            preferences.shortcuts.windowOrApplication,
            ScreenshotShortcutSet.defaults.windowOrApplication)
    }

    func testRestoreDefaultsExplicitlyAdoptsNewBindingAndSurvivesRelaunch() throws {
        let (defaults, suite, home) = try makeLaunchFixture()
        defaults.set(false, forKey: ScreenshotPreferences.shutterSoundKey)
        let preferences = ScreenshotPreferences(defaults: defaults)
        let root = home.appendingPathComponent("Recordings")
        preferences.prepareForLaunch(recordingsRoot: root, home: home, preferencesDomainName: suite)
        XCTAssertEqual(preferences.shortcuts, .legacyDefaults)
        preferences.restoreDefaultShortcuts()
        let relaunched = ScreenshotPreferences(defaults: defaults)
        relaunched.prepareForLaunch(recordingsRoot: root, home: home, preferencesDomainName: suite)
        XCTAssertEqual(relaunched.shortcuts, .defaults)
        XCTAssertFalse(relaunched.playShutterSound)
    }

    private func makeLaunchFixture() throws -> (UserDefaults, String, URL) {
        let suite = "ScreenshotLaunchTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: home)
        }
        return (defaults, suite, home)
    }

    private func makeDefaults() throws -> UserDefaults {
        let suite = "ScreenshotPreferencesTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }
}
