import Foundation
import RecordMedia
import XCTest

final class SegmentOutputTests: XCTestCase {
    func testCreatesUniqueHiddenPartialAlongsideFinalSegment() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let finalURL = directory.appendingPathComponent("segment-0001.mov")
        let identifier = try XCTUnwrap(
            UUID(uuidString: "00000000-0000-0000-0000-000000000001")
        )

        let output = try SegmentOutput(finalURL: finalURL, identifier: identifier)

        XCTAssertEqual(output.finalURL, finalURL)
        XCTAssertEqual(
            output.partialURL.lastPathComponent,
            ".segment-0001.00000000-0000-0000-0000-000000000001.partial.mov"
        )
    }

    func testNeverOverwritesAnExistingFinalSegment() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let finalURL = directory.appendingPathComponent("segment-0001.mov")
        let existing = Data("keep".utf8)
        try existing.write(to: finalURL)

        XCTAssertThrowsError(try SegmentOutput(finalURL: finalURL)) { error in
            XCTAssertEqual(error as? SegmentWriterError, .outputAlreadyExists(finalURL))
        }
        XCTAssertEqual(try Data(contentsOf: finalURL), existing)
    }

    func testOutputSetKeepsVideoAndAudioInIndependentFiles() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let identifier = try XCTUnwrap(
            UUID(uuidString: "00000000-0000-0000-0000-000000000001")
        )

        let outputs = try SegmentOutputSet(
            screenURL: directory.appendingPathComponent("recording.mov"),
            includesSystemAudio: true,
            includesMicrophone: true,
            identifier: identifier
        )

        XCTAssertEqual(outputs[.screen]?.finalURL.lastPathComponent, "recording.mov")
        XCTAssertEqual(outputs[.systemAudio]?.finalURL.lastPathComponent, "system.caf")
        XCTAssertEqual(outputs[.microphone]?.finalURL.lastPathComponent, "mic.caf")
        XCTAssertEqual(Set(outputs.outputs.values.map(\.partialURL)).count, 3)
    }

    func testOutputSetAcceptsExplicitImmutableSegmentNames() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let outputs = try SegmentOutputSet(
            finalURLs: [
                .screen: directory.appendingPathComponent("segment-0002.mov"),
                .systemAudio: directory.appendingPathComponent("segment-0002-system.caf"),
                .microphone: directory.appendingPathComponent("segment-0002-mic.caf"),
            ]
        )

        XCTAssertEqual(outputs[.screen]?.finalURL.lastPathComponent, "segment-0002.mov")
        XCTAssertEqual(
            outputs[.systemAudio]?.finalURL.lastPathComponent,
            "segment-0002-system.caf"
        )
        XCTAssertEqual(outputs[.microphone]?.finalURL.lastPathComponent, "segment-0002-mic.caf")
    }

    func testOutputSetRejectsDuplicateDestinations() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let duplicate = directory.appendingPathComponent("segment.mov")

        XCTAssertThrowsError(
            try SegmentOutputSet(finalURLs: [.screen: duplicate, .microphone: duplicate])
        ) { error in
            XCTAssertEqual(error as? SegmentWriterError, .invalidOutputURL)
        }
    }

    func testRejectsNonMovieAndMissingDirectoryTargets() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        XCTAssertThrowsError(
            try SegmentOutput(finalURL: directory.appendingPathComponent("segment.mp4"))
        ) { error in
            XCTAssertEqual(error as? SegmentWriterError, .invalidOutputURL)
        }
        let missingDirectory = directory.appendingPathComponent("missing", isDirectory: true)
        let finalURL = missingDirectory.appendingPathComponent("segment.mov")
        XCTAssertThrowsError(try SegmentOutput(finalURL: finalURL)) { error in
            XCTAssertEqual(
                error as? SegmentWriterError,
                .outputDirectoryUnavailable(missingDirectory)
            )
        }
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "record-segment-output-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        return directory
    }
}
