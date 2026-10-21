import AppKit
@testable import Record
import RecordCore
import XCTest

@MainActor
final class RecordingAudioPreferencesTests: XCTestCase {
    func testGainControlDefaultsOffAndOptInSurvivesReopeningPreferences() throws {
        let defaults = try makeDefaults()
        let preferences = RecordingAudioPreferences(defaults: defaults, configuration: .init())
        XCTAssertFalse(preferences.automaticGainControl)
        preferences.automaticGainControl = true
        XCTAssertTrue(
            RecordingAudioPreferences(defaults: defaults, configuration: .init())
                .automaticGainControl)
    }

    func testExplicitOffOverridesAnAdvancedConfigurationOptIn() throws {
        let defaults = try makeDefaults()
        let preferences = RecordingAudioPreferences(
            defaults: defaults, configuration: .init(micAutomaticGainControl: true))
        XCTAssertTrue(preferences.automaticGainControl)
        preferences.automaticGainControl = false
        XCTAssertFalse(preferences.automaticGainControl)
    }

    func testSettingsPersistsGainControlAndLocksItDuringCapture() throws {
        let defaults = try makeDefaults()
        let preferences = RecordingAudioPreferences(defaults: defaults, configuration: .init())
        let controller = SettingsWindowController(
            screenshotPreferences: .init(defaults: defaults), audioPreferences: preferences)
        let checkbox = controller.automaticGainControlCheckbox
        XCTAssertEqual(checkbox.state, .off)
        XCTAssertTrue(checkbox.isEnabled)
        checkbox.performClick(nil)
        XCTAssertTrue(preferences.automaticGainControl)

        let reopened = SettingsWindowController(
            screenshotPreferences: .init(defaults: defaults), audioPreferences: preferences)
        XCTAssertEqual(reopened.automaticGainControlCheckbox.state, .on)
        controller.updateInteractionAvailability(
            .init(destinationSelectionEnabled: false, capturePrivacyEnabled: false))
        XCTAssertFalse(checkbox.isEnabled)
        checkbox.state = .off
        controller.automaticGainControlChanged()
        XCTAssertTrue(preferences.automaticGainControl)
        controller.updateInteractionAvailability(.idle)
        XCTAssertTrue(checkbox.isEnabled)
        XCTAssertEqual(checkbox.state, .on)
    }

    func testExplicitMicrophoneDisablesControlWithoutErasingPreference() throws {
        let defaults = try makeDefaults()
        let preferences = RecordingAudioPreferences(defaults: defaults, configuration: .init())
        preferences.automaticGainControl = true
        preferences.microphoneUID = "synthetic-input"
        let controller = SettingsWindowController(
            screenshotPreferences: .init(defaults: defaults), audioPreferences: preferences)
        XCTAssertFalse(controller.automaticGainControlCheckbox.isEnabled)
        XCTAssertEqual(controller.automaticGainControlCheckbox.state, .on)
        preferences.microphoneUID = nil
        controller.refreshAudioDevices()
        XCTAssertTrue(controller.automaticGainControlCheckbox.isEnabled)
        XCTAssertTrue(preferences.automaticGainControl)
    }

    func testGainOptInDoesNotOverrideDisabledVoiceProcessing() throws {
        let defaults = try makeDefaults()
        let preferences = RecordingAudioPreferences(
            defaults: defaults,
            configuration: .init(micVoiceProcessing: false, micAutomaticGainControl: true))
        let controller = SettingsWindowController(
            screenshotPreferences: .init(defaults: defaults), audioPreferences: preferences)
        XCTAssertFalse(preferences.usesVoiceProcessing)
        XCTAssertFalse(controller.automaticGainControlCheckbox.isEnabled)
        XCTAssertEqual(controller.automaticGainControlCheckbox.state, .on)
    }

    func testVoiceProcessingAndZoomProtectionPersistIndependently() throws {
        let defaults = try makeDefaults()
        let preferences = RecordingAudioPreferences(defaults: defaults, configuration: .init())
        XCTAssertTrue(preferences.voiceProcessing)
        XCTAssertTrue(preferences.disableVoiceProcessingForZoom)
        preferences.voiceProcessing = false
        preferences.disableVoiceProcessingForZoom = false
        let reopened = RecordingAudioPreferences(defaults: defaults, configuration: .init())
        XCTAssertFalse(reopened.voiceProcessing)
        XCTAssertFalse(reopened.disableVoiceProcessingForZoom)
        XCTAssertFalse(reopened.automaticGainControl)
    }

    func testSettingsOverridesAdvancedVoiceProcessingConfiguration() throws {
        let preferences = RecordingAudioPreferences(
            defaults: try makeDefaults(),
            configuration: .init(micVoiceProcessing: false, micDisableVoiceProcessingForZoom: false)
        )
        XCTAssertFalse(preferences.voiceProcessing)
        XCTAssertFalse(preferences.disableVoiceProcessingForZoom)
        preferences.voiceProcessing = true
        preferences.disableVoiceProcessingForZoom = true
        XCTAssertTrue(preferences.usesVoiceProcessing)
        XCTAssertTrue(preferences.disableVoiceProcessingForZoom)
    }

    func testVoiceControlsLockAndPreserveDependentPreferences() throws {
        let defaults = try makeDefaults()
        let preferences = RecordingAudioPreferences(defaults: defaults, configuration: .init())
        let controller = SettingsWindowController(
            screenshotPreferences: .init(defaults: defaults), audioPreferences: preferences)
        XCTAssertEqual(controller.voiceProcessingCheckbox.state, .on)
        XCTAssertEqual(controller.zoomCompatibilityCheckbox.state, .on)
        controller.voiceProcessingCheckbox.performClick(nil)
        XCTAssertFalse(preferences.voiceProcessing)
        XCTAssertFalse(controller.zoomCompatibilityCheckbox.isEnabled)
        XCTAssertFalse(controller.automaticGainControlCheckbox.isEnabled)
        XCTAssertTrue(preferences.disableVoiceProcessingForZoom)
        controller.voiceProcessingCheckbox.performClick(nil)
        XCTAssertTrue(controller.zoomCompatibilityCheckbox.isEnabled)
        controller.zoomCompatibilityCheckbox.performClick(nil)
        XCTAssertFalse(preferences.disableVoiceProcessingForZoom)
        controller.updateInteractionAvailability(
            .init(destinationSelectionEnabled: false, capturePrivacyEnabled: false))
        XCTAssertFalse(controller.voiceProcessingCheckbox.isEnabled)
        XCTAssertFalse(controller.zoomCompatibilityCheckbox.isEnabled)
        controller.voiceProcessingCheckbox.state = .off
        controller.zoomCompatibilityCheckbox.state = .on
        controller.voiceProcessingChanged()
        controller.zoomCompatibilityChanged()
        XCTAssertTrue(preferences.voiceProcessing)
        XCTAssertFalse(preferences.disableVoiceProcessingForZoom)
        controller.updateInteractionAvailability(.idle)
        XCTAssertEqual(controller.voiceProcessingCheckbox.state, .on)
        XCTAssertEqual(controller.zoomCompatibilityCheckbox.state, .off)
        preferences.microphoneUID = "synthetic-input"
        controller.refreshAudioDevices()
        XCTAssertFalse(controller.voiceProcessingCheckbox.isEnabled)
        XCTAssertFalse(controller.zoomCompatibilityCheckbox.isEnabled)
    }

    private func makeDefaults() throws -> UserDefaults {
        let suite = "RecordingAudioPreferencesTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }
}
