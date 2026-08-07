import Foundation
import RecordCore
import XCTest

final class AppConfigurationTests: XCTestCase {
    func testPartialConfigurationUsesDocumentedDefaults() throws {
        let data = Data(#"{"transcription":{"enabled":false}}"#.utf8)

        let configuration = try AppConfiguration.decode(data)

        XCTAssertEqual(configuration.schemaVersion, 1)
        XCTAssertFalse(configuration.transcription.enabled)
        XCTAssertEqual(configuration.transcription.engine, "parakeet")
        XCTAssertEqual(configuration.transcription.model, ParakeetModelID.v3.rawValue)
        XCTAssertNil(configuration.transcription.executable)
        XCTAssertEqual(configuration.transcription.language, "auto")
        XCTAssertFalse(configuration.micVoiceProcessing)
    }

    func testMacWhisperRequiresAnExplicitModel() {
        let data = Data(#"{"transcription":{"engine":"macwhisper"}}"#.utf8)

        XCTAssertThrowsError(try AppConfiguration.decode(data)) { error in
            XCTAssertEqual(
                error as? AppConfiguration.ConfigurationError,
                .transcriptionModelRequired("macwhisper")
            )
        }
    }

    func testMacWhisperConfigurationIsTypedAndNormalized() throws {
        let data = Data(
            #"{"transcription":{"engine":"MACWHISPER","model":"whisperkit:openai_whisper-small","executable":"/Applications/MacWhisper.app/Contents/MacOS/mw","language":"EN"}}"#
                .utf8
        )

        let transcription = try AppConfiguration.decode(data).transcription

        XCTAssertEqual(transcription.engine, "macwhisper")
        XCTAssertEqual(transcription.model, "whisperkit:openai_whisper-small")
        XCTAssertEqual(
            transcription.executable,
            "/Applications/MacWhisper.app/Contents/MacOS/mw"
        )
        XCTAssertEqual(transcription.language, "en")
    }

    func testRejectsUnsupportedTranscriptionEngine() {
        let data = Data(#"{"transcription":{"engine":"cloud"}}"#.utf8)

        XCTAssertThrowsError(try AppConfiguration.decode(data)) { error in
            XCTAssertEqual(
                error as? AppConfiguration.ConfigurationError,
                .unsupportedTranscriptionEngine("cloud")
            )
        }
    }

    func testRejectsRelativeMacWhisperExecutable() {
        let data = Data(
            #"{"transcription":{"engine":"macwhisper","model":"whisperkit:openai_whisper-small","executable":"mw"}}"#
                .utf8
        )

        XCTAssertThrowsError(try AppConfiguration.decode(data)) { error in
            XCTAssertEqual(
                error as? AppConfiguration.ConfigurationError,
                .transcriptionExecutableMustBeAbsolute("mw")
            )
        }
    }

    func testRejectsInvalidTranscriptionLanguage() {
        let data = Data(#"{"transcription":{"language":"english"}}"#.utf8)

        XCTAssertThrowsError(try AppConfiguration.decode(data)) { error in
            XCTAssertEqual(
                error as? AppConfiguration.ConfigurationError,
                .invalidTranscriptionLanguage("english")
            )
        }
    }

    func testRejectsRelativeCompletionHookExecutable() {
        let data = Data(
            #"{"completion_hook":{"executable":"script.sh","arguments":[]}}"#.utf8
        )

        XCTAssertThrowsError(try AppConfiguration.decode(data)) { error in
            XCTAssertEqual(
                error as? AppConfiguration.ConfigurationError,
                .hookExecutableMustBeAbsolute("script.sh")
            )
        }
    }

    func testRecordingsDirectoryResolutionExpandsOnlyLeadingTilde() {
        let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        let configuration = AppConfiguration(recordingsDirectory: "~/Recordings/Record")

        let result = RecordPaths.resolveRecordingsDirectory(
            cliOverride: nil,
            configuration: configuration,
            home: home
        )

        XCTAssertEqual(result.path, "/Users/tester/Recordings/Record")
    }

    func testCLIRecordingsDirectoryWinsOverConfiguration() {
        let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        let configuration = AppConfiguration(recordingsDirectory: "~/configured")

        let result = RecordPaths.resolveRecordingsDirectory(
            cliOverride: "/Volumes/Fast/Recordings",
            configuration: configuration,
            home: home
        )

        XCTAssertEqual(result.path, "/Volumes/Fast/Recordings")
    }

    func testDefaultExportsDirectoryIsDesktop() {
        let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)

        let result = RecordPaths.defaultExportsDirectory(home: home)

        XCTAssertEqual(result.path, "/Users/tester/Desktop")
    }

    func testModelRegistrySupportsShortAliases() throws {
        XCTAssertEqual(try ParakeetModelID(configurationValue: "v2"), .v2)
        XCTAssertEqual(try ParakeetModelID(configurationValue: "V3"), .v3)
        XCTAssertThrowsError(try ParakeetModelID(configurationValue: "cloud-model"))
    }
}
