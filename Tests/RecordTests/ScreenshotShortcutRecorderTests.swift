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

    func testSettingsWindowFitsLongestLabelAndFooterControls() throws {
        let suite = "UnifiedSettingsLayoutTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let controller = SettingsWindowController(
            screenshotPreferences: ScreenshotPreferences(defaults: defaults)
        )
        controller.select(section: .screenshots)
        let window = try XCTUnwrap(controller.window)
        let contentView = try XCTUnwrap(window.contentView)

        contentView.layoutSubtreeIfNeeded()

        let descendants = allSubviews(of: contentView)
        let longestLabel = try XCTUnwrap(
            descendants.compactMap { $0 as? NSTextField }.first {
                $0.stringValue == ScreenshotCaptureKind.windowOrApplication.displayName
            }
        )
        XCTAssertGreaterThanOrEqual(
            longestLabel.frame.width + 0.5,
            longestLabel.intrinsicContentSize.width
        )

        for title in ["Restore Defaults", "Open macOS Keyboard Shortcuts…"] {
            let button = try XCTUnwrap(
                descendants.compactMap { $0 as? NSButton }.first { $0.title == title }
            )
            let frame = button.convert(button.bounds, to: contentView)
            XCTAssertGreaterThanOrEqual(frame.minX, contentView.bounds.minX - 0.5)
            XCTAssertLessThanOrEqual(frame.maxX, contentView.bounds.maxX + 0.5)
            XCTAssertGreaterThanOrEqual(frame.minY, contentView.bounds.minY - 0.5)
            XCTAssertLessThanOrEqual(frame.maxY, contentView.bounds.maxY + 0.5)
        }
    }

    func testUnifiedSettingsExposesGeneralScreenshotAndRecordingSections() throws {
        let suite = "UnifiedSettingsSectionsTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let controller = SettingsWindowController(
            screenshotPreferences: ScreenshotPreferences(defaults: defaults)
        )

        XCTAssertEqual(controller.selectedSection, .general)
        controller.select(section: .screenshots)
        XCTAssertEqual(controller.selectedSection, .screenshots)
        controller.select(section: .recording)
        XCTAssertEqual(controller.selectedSection, .recording)

        let contentView = try XCTUnwrap(controller.window?.contentView)
        let text = allSubviews(of: contentView)
            .compactMap { ($0 as? NSTextField)?.stringValue }
        XCTAssertEqual(text.filter { $0 == "Save to" }.count, 1)
        XCTAssertTrue(text.contains("Window or Application"))
        XCTAssertTrue(text.contains("Template"))
        XCTAssertTrue(text.contains("Model"))
    }

    func testUnifiedSettingsOwnsTranscriptionPresentation() throws {
        let suite = "UnifiedSettingsTranscriptionTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let controller = SettingsWindowController(
            screenshotPreferences: ScreenshotPreferences(defaults: defaults)
        )

        controller.updateTranscriptionEngine(
            .parakeet,
            macWhisperAvailable: false,
            parakeetModelAvailable: true
        )
        XCTAssertFalse(controller.isMacWhisperOptionVisible)
        controller.updateTranscriptionEngine(
            .parakeet,
            macWhisperAvailable: true,
            parakeetModelAvailable: true
        )
        XCTAssertTrue(controller.isMacWhisperOptionVisible)

        controller.updateTranscriptRefinement(
            enabled: true,
            available: false,
            detail: "Unavailable"
        )
        XCTAssertTrue(controller.isTranscriptRefinementSelected)
        XCTAssertFalse(controller.isTranscriptRefinementEnabled)
    }

    func testUnifiedSettingsAppliesSharedInteractionAvailability() throws {
        let suite = "UnifiedSettingsAvailabilityTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let controller = SettingsWindowController(
            screenshotPreferences: ScreenshotPreferences(defaults: defaults)
        )

        controller.updateInteractionAvailability(
            SettingsInteractionAvailability(
                destinationSelectionEnabled: false,
                capturePrivacyEnabled: false
            )
        )
        XCTAssertFalse(controller.isDestinationSelectionEnabled)
        XCTAssertFalse(controller.areCapturePrivacyControlsEnabled)

        controller.updateInteractionAvailability(.idle)
        XCTAssertTrue(controller.isDestinationSelectionEnabled)
        XCTAssertTrue(controller.areCapturePrivacyControlsEnabled)
    }

    private func allSubviews(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + allSubviews(of: $0) }
    }
}
