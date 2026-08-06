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

    private func makeDefaults() throws -> UserDefaults {
        let suite = "com.aindaco.record.transcription-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suite)
        }
        return defaults
    }
}
