import ArgumentParser
@testable import Record
import XCTest

final class TranscribeFilesTests: XCTestCase {
    func testMultipleLocalPathsAndDestinationAreParsedWithoutRecordingCommands() throws {
        let command = try XCTUnwrap(
            RecordCommand.parseAsRoot([
                "transcribe", "first.wav", "second.m4a", "--output", "sessions",
            ]) as? TranscribeFiles)
        XCTAssertEqual(command.files, ["first.wav", "second.m4a"])
        XCTAssertEqual(command.output, "sessions")
        XCTAssertFalse(command.authorize)
        XCTAssertTrue(try RecordCommand.parseAsRoot([]) is Run)
        XCTAssertThrowsError(try RecordCommand.parseAsRoot(["start"]))
        XCTAssertThrowsError(
            try RecordCommand.parseAsRoot(["transcribe", "https://example.invalid/audio.wav"]))
        XCTAssertThrowsError(try RecordCommand.parseAsRoot(["transcribe"]))
        XCTAssertTrue(
            try XCTUnwrap(
                RecordCommand.parseAsRoot(["transcribe", "--authorize"]) as? TranscribeFiles
            ).authorize)
    }
}
