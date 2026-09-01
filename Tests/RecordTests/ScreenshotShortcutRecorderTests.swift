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
        let suite = "ScreenshotSettingsLayoutTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let controller = ScreenshotSettingsWindowController(
            preferences: ScreenshotPreferences(defaults: defaults)
        )
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

    private func allSubviews(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + allSubviews(of: $0) }
    }
}
