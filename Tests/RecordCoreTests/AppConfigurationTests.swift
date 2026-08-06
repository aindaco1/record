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
        XCTAssertFalse(configuration.micVoiceProcessing)
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

    func testModelRegistrySupportsShortAliases() throws {
        XCTAssertEqual(try ParakeetModelID(configurationValue: "v2"), .v2)
        XCTAssertEqual(try ParakeetModelID(configurationValue: "V3"), .v3)
        XCTAssertThrowsError(try ParakeetModelID(configurationValue: "cloud-model"))
    }
}
