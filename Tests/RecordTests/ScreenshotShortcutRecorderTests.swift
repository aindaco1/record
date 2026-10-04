@testable import Record
import AppKit
import RecordCore
import XCTest

@MainActor
final class ScreenshotShortcutRecorderTests: XCTestCase {
    @MainActor
    func testSessionsProgressClearsWhenTranscriptionFinishesOnAnotherPage() {
        let sessions = RecentSessionsViewController()
        sessions.updateTranscription(
            .progress(session: "synthetic", stage: "Loading engine", queued: 0), isVisible: false)
        XCTAssertEqual(sessions.activeProgress?.session, "synthetic")
        sessions.updateTranscription(.idle, isVisible: false)
        XCTAssertNil(sessions.activeProgress)
    }

    func testSpanishLanguageControlsFitAtMinimumWindowWidth() throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let controller = SettingsWindowController(screenshotPreferences: .init(defaults: defaults))
        controller.updateSpeechLanguage(engine: .parakeet, preferred: "auto")
        controller.transcriptionPopup.item(at: 0)?.title = L10n.text(
            "Parakeet (Default)", language: .spanish)
        controller.speechLanguagePopup.item(at: 0)?.title = L10n.text(
            "Automatic", language: .spanish)
        let window = try XCTUnwrap(controller.window)
        window.setContentSize(window.contentMinSize)
        controller.select(section: .transcription)
        window.contentView?.layoutSubtreeIfNeeded()
        for popup in [controller.transcriptionPopup, controller.speechLanguagePopup] {
            let title = try XCTUnwrap(popup.selectedItem?.title)
            let width = (title as NSString).size(withAttributes: [
                .font: popup.font ?? NSFont.systemFont(ofSize: 13)
            ]).width
            XCTAssertGreaterThanOrEqual(popup.frame.width, width + 24)
        }
    }

    func testStoppingInputTestUsesStateInsteadOfEnglishMessageText() async {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let controller = SettingsWindowController(screenshotPreferences: .init(defaults: defaults))
        controller.inputTestTask = Task {}
        controller.audioStatus.stringValue = "Escuchando: prueba sintética"
        controller.stopInputTest()
        XCTAssertEqual(controller.audioStatus.stringValue, "Input test stopped.")
        controller.inputTestTask = Task {}
        controller.audioStatus.stringValue = "Prueba terminada"
        controller.stopInputTest(preserveMessage: true)
        XCTAssertEqual(controller.audioStatus.stringValue, "Prueba terminada")
    }

    func testIdleSettingsDoesNotRetainActivityFromAFinishedRecording() throws {
        let suite = "IdleAudioSettingsTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let controller = SettingsWindowController(screenshotPreferences: .init(defaults: defaults))
        controller.updateAudioLevels((microphone: 0.7, system: 0.8), configuration: .init())
        controller.updateInteractionAvailability(.idle)
        let meters = allSubviews(of: try XCTUnwrap(controller.window?.contentView))
            .compactMap { $0 as? NSLevelIndicator }
        XCTAssertEqual(meters.count, 2)
        XCTAssertTrue(meters.allSatisfy { $0.doubleValue == 0 })
    }
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
        controller.select(section: .shortcuts)
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

        for title in ["Restore Screenshot Defaults", "macOS Keyboard Shortcuts…"] {
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

        XCTAssertEqual(controller.selectedSection, .recording)
        let firstRow = try XCTUnwrap(
            controller.tableView(controller.sidebar, viewFor: nil, row: 0))
        XCTAssertTrue(
            allSubviews(of: firstRow).compactMap { ($0 as? NSTextField)?.stringValue }
                .contains("General"))
        controller.sidebar.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        XCTAssertEqual(controller.selectedSection, .general)
        XCTAssertFalse(try XCTUnwrap(controller.pageViews[.general]).isHidden)
        XCTAssertTrue(try XCTUnwrap(controller.pageViews[.recording]).isHidden)
        controller.select(section: .screenshots)
        XCTAssertEqual(controller.selectedSection, .screenshots)
        controller.select(section: .recording)
        XCTAssertEqual(controller.selectedSection, .recording)

        let contentView = try XCTUnwrap(controller.window?.contentView)
        let text = allSubviews(of: contentView)
            .compactMap { ($0 as? NSTextField)?.stringValue }
        XCTAssertEqual(text.filter { $0 == "Save to" }.count, 1)
        XCTAssertTrue(text.contains("Window or Application"))
        XCTAssertTrue(text.contains("Name template"))
        XCTAssertTrue(text.contains("Parakeet model"))
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

        controller.updateTranscriptionEngine(
            .parakeet,
            macWhisperAvailable: true,
            parakeetModelAvailable: false,
            parakeetSetupInProgress: true
        )
        XCTAssertEqual(controller.parakeetStatus, "Downloading and verifying…")
        XCTAssertEqual(controller.parakeetSetupButtonTitle, "Downloading…")
        XCTAssertFalse(controller.isParakeetSetupButtonEnabled)

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
        XCTAssertFalse(controller.startRecordingButton.isEnabled)
        XCTAssertFalse(controller.checkPermissionsButton.isEnabled)
        XCTAssertFalse(controller.screenSourcePopup.isEnabled)

        controller.updateInteractionAvailability(.idle)
        XCTAssertTrue(controller.isDestinationSelectionEnabled)
        XCTAssertTrue(controller.areCapturePrivacyControlsEnabled)
        XCTAssertTrue(controller.startRecordingButton.isEnabled)
        controller.recordingMode.selectedSegment = 1
        controller.recordingModeChanged()
        XCTAssertFalse(controller.screenSourcePopup.isEnabled)
        XCTAssertEqual(controller.startRecordingButton.title, "Start Audio Recording")
    }

    func testSidebarKeepsEveryDestinationInTheSameWindow() throws {
        let suite = "SidebarSettingsTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let controller = SettingsWindowController(screenshotPreferences: .init(defaults: defaults))
        let window = try XCTUnwrap(controller.window)
        for section in SettingsWindowController.Section.allCases {
            controller.select(section: section)
            XCTAssertTrue(controller.window === window)
            XCTAssertEqual(controller.sidebar.selectedRow, section.rawValue)
            XCTAssertEqual(controller.pageViews.filter { !$0.value.isHidden }.map(\.key), [section])
        }
        XCTAssertTrue(controller.pageViews[.sessions] === controller.sessions.view)
        let buttons = allSubviews(of: try XCTUnwrap(window.contentView)).compactMap {
            $0 as? NSButton
        }
        XCTAssertFalse(
            buttons.contains {
                ["Ready to Record…", "Recent Sessions…", "Edit…"].contains($0.title)
            })
    }

    func testInlineNameEditingSavesOnlyValidTemplatesAndUsesPlaceholderClipboard() throws {
        let suite = "InlineNameTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let controller = SettingsWindowController(screenshotPreferences: .init(defaults: defaults))
        var saved: [String] = []
        controller.onUpdateRecordingNameTemplate = { saved.append($0) }
        controller.recordingTemplateField.stringValue = "Meeting {clipboard}"
        let change = Notification(
            name: NSControl.textDidChangeNotification, object: controller.recordingTemplateField)
        controller.controlTextDidChange(change)
        XCTAssertEqual(saved, ["Meeting {clipboard}"])
        XCTAssertEqual(controller.recordingNamePreview.stringValue, "Example: Meeting Clipboard")
        controller.recordingTemplateField.stringValue = "{unsupported}"
        controller.controlTextDidChange(change)
        XCTAssertEqual(saved.count, 1)
        XCTAssertTrue(controller.recordingNamePreview.stringValue.contains("last valid template"))
    }

    func testSettingsTextFieldsSupportCommandAWithoutAnEditMenu() throws {
        let window = SettingsWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
            styleMask: [.titled], backing: .buffered, defer: false)
        let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 100))
        editor.string = "Search or template text"
        window.contentView?.addSubview(editor)
        XCTAssertTrue(window.makeFirstResponder(editor))
        editor.setSelectedRange(NSRange(location: 0, length: 0))
        let event = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero,
                modifierFlags: .command, timestamp: 0, windowNumber: window.windowNumber,
                context: nil, characters: "a", charactersIgnoringModifiers: "a", isARepeat: false,
                keyCode: 0))
        XCTAssertTrue(window.performKeyEquivalent(with: event))
        XCTAssertEqual(
            editor.selectedRange(), NSRange(location: 0, length: editor.string.utf16.count))
    }

    func testWindowEditingCommandsDoNotInterceptShortcutAssignment() throws {
        let window = SettingsWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
            styleMask: [.titled], backing: .buffered, defer: false)
        let recorder = ShortcutRecorderButton()
        window.contentView?.addSubview(recorder)
        var recorded: ScreenshotShortcut?
        recorder.onRecord = { recorded = $0 }
        recorder.performClick(nil)
        let event = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero,
                modifierFlags: .command, timestamp: 0, windowNumber: window.windowNumber,
                context: nil, characters: "w", charactersIgnoringModifiers: "w", isARepeat: false,
                keyCode: 13))
        XCTAssertTrue(window.performKeyEquivalent(with: event))
        XCTAssertEqual(recorded?.keyCode, 13)
        XCTAssertEqual(recorded?.modifiers, .command)
        XCTAssertFalse(recorder.isRecordingShortcut)
    }

    func testAllPagesFitHorizontallyAtMinimumSize() throws {
        let suite = "MinimumSettingsTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let controller = SettingsWindowController(screenshotPreferences: .init(defaults: defaults))
        let window = try XCTUnwrap(controller.window)
        window.setContentSize(window.contentMinSize)
        let content = try XCTUnwrap(window.contentView)
        for section in SettingsWindowController.Section.allCases {
            controller.select(section: section)
            content.layoutSubtreeIfNeeded()
            let page = try XCTUnwrap(controller.pageViews[section])
            for control in allSubviews(of: page).compactMap({ $0 as? NSControl })
            where !control.isHiddenOrHasHiddenAncestor {
                let frame = control.convert(control.bounds, to: content)
                XCTAssertGreaterThanOrEqual(frame.minX, 190, "\(section): \(control)")
                XCTAssertLessThanOrEqual(
                    frame.maxX, content.bounds.maxX + 1, "\(section): \(control)")
            }
        }
    }

    private func allSubviews(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + allSubviews(of: $0) }
    }
}
