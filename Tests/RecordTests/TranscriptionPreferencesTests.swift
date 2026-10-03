import Foundation
@testable import Record
import RecordCore
import XCTest

@MainActor
final class TranscriptionPreferencesTests: XCTestCase {
    func testConfigurationRemainsBaselineWithoutMenuOverride() throws {
        let defaults = try makeDefaults()
        let configuration = AppConfiguration.Transcription(
            engine: "macwhisper",
            model: "whisperkit:custom-local",
            language: "en"
        )

        let selection = TranscriptionPreferences.effectiveSelection(
            configuration: configuration,
            defaults: defaults
        )

        XCTAssertEqual(selection.engine, .macwhisper)
        XCTAssertEqual(selection.model, "whisperkit:custom-local")
        XCTAssertEqual(selection.language, "en")
    }

    func testSelectingMacWhisperPersistsSafeLocalDefault() throws {
        let defaults = try makeDefaults()

        TranscriptionPreferences.select(.macwhisper, defaults: defaults)
        let selection = TranscriptionPreferences.effectiveSelection(
            configuration: .init(),
            defaults: defaults
        )

        XCTAssertEqual(selection.engine, .macwhisper)
        XCTAssertEqual(selection.model, "whisperkit:openai_whisper-small")
        XCTAssertEqual(selection.language, "auto")
    }

    func testSwitchingBackToParakeetDoesNotReuseMacWhisperModel() throws {
        let defaults = try makeDefaults()
        TranscriptionPreferences.select(.macwhisper, defaults: defaults)
        TranscriptionPreferences.select(.parakeet, defaults: defaults)

        let selection = TranscriptionPreferences.effectiveSelection(
            configuration: .init(),
            defaults: defaults
        )

        XCTAssertEqual(selection.engine, .parakeet)
        XCTAssertEqual(selection.model, ParakeetModelID.v3.rawValue)
    }

    func testInvalidPersistedEngineFailsClosedToConfiguration() throws {
        let defaults = try makeDefaults()
        defaults.set("cloud", forKey: "transcription.engine")

        let selection = TranscriptionPreferences.effectiveSelection(
            configuration: .init(),
            defaults: defaults
        )

        XCTAssertEqual(selection.engine, .parakeet)
    }

    func testParakeetAlwaysUsesAutomaticLanguageWithoutErasingMacWhisperPreference() throws {
        let defaults = try makeDefaults()
        TranscriptionPreferences.setLanguage("es", defaults: defaults)
        TranscriptionPreferences.select(.parakeet, defaults: defaults)
        XCTAssertEqual(
            TranscriptionPreferences.effectiveSelection(configuration: .init(), defaults: defaults)
                .language, "auto")
        XCTAssertEqual(
            TranscriptionPreferences.preferredLanguage(configuration: .init(), defaults: defaults),
            "es")
        TranscriptionPreferences.select(.macwhisper, defaults: defaults)
        XCTAssertEqual(
            TranscriptionPreferences.effectiveSelection(configuration: .init(), defaults: defaults)
                .language, "es")
    }

    func testAdvancedLanguageSurvivesUntilExplicitlyChanged() throws {
        let defaults = try makeDefaults()
        let configuration = AppConfiguration.Transcription(engine: "macwhisper", language: "fr")
        XCTAssertEqual(
            TranscriptionPreferences.effectiveSelection(
                configuration: configuration, defaults: defaults
            ).language, "fr")
        TranscriptionPreferences.setLanguage("invalid", defaults: defaults)
        XCTAssertEqual(
            TranscriptionPreferences.effectiveSelection(
                configuration: configuration, defaults: defaults
            ).language, "fr")
    }

    func testRefinementUsesConfigurationAsItsBaseline() throws {
        let defaults = try makeDefaults()
        let configuration = AppConfiguration.Transcription(
            refineWithAppleIntelligence: true
        )

        XCTAssertTrue(
            TranscriptionPreferences.refinementEnabled(
                configuration: configuration,
                defaults: defaults
            )
        )
    }

    func testRefinementPreferenceOverridesConfiguration() throws {
        let defaults = try makeDefaults()
        let configuration = AppConfiguration.Transcription(
            refineWithAppleIntelligence: true
        )

        TranscriptionPreferences.setRefinementEnabled(false, defaults: defaults)

        XCTAssertFalse(
            TranscriptionPreferences.refinementEnabled(
                configuration: configuration,
                defaults: defaults
            )
        )
    }

    private func makeDefaults() throws -> UserDefaults {
        let suite = "com.aindaco.record.transcription-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suite)
        }
        return defaults
    }
}
