import Foundation
@testable import Record
import XCTest

final class NotificationDirectoryReferenceTests: XCTestCase {
    func testRoundTripsRootAndDirectSessionWithoutPersistingAbsolutePaths() throws {
        let temporaryRoot = try makeTemporaryDirectory()
        let root = temporaryRoot.appendingPathComponent("Recordings", isDirectory: true)
        let session = root.appendingPathComponent("2026.08.06-1230", isDirectory: true)
        try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
        let reference = NotificationDirectoryReference(recordingsRoot: root)

        XCTAssertEqual(reference.token(for: root), ".")
        let token = try XCTUnwrap(reference.token(for: session))
        XCTAssertEqual(token, "2026.08.06-1230")
        XCTAssertFalse(token.contains(root.path))
        XCTAssertEqual(reference.resolve(token), session.standardizedFileURL)
    }

    func testRejectsOutsideNestedAndMalformedDestinations() {
        let root = URL(fileURLWithPath: "/tmp/Recordings", isDirectory: true)
        let reference = NotificationDirectoryReference(recordingsRoot: root)

        XCTAssertNil(
            reference.token(
                for: URL(fileURLWithPath: "/tmp/Elsewhere", isDirectory: true)
            )
        )
        XCTAssertNil(
            reference.token(
                for: root.appendingPathComponent("session/private", isDirectory: true)
            )
        )
        for token in ["", "..", "../Elsewhere", "session/private", "session:private"] {
            XCTAssertNil(reference.resolve(token))
        }
    }

    func testRejectsSessionSymlinkThatEscapesRecordingsRoot() throws {
        let temporaryRoot = try makeTemporaryDirectory()
        let recordingsRoot = temporaryRoot.appendingPathComponent(
            "Recordings",
            isDirectory: true
        )
        let outside = temporaryRoot.appendingPathComponent("Outside", isDirectory: true)
        try FileManager.default.createDirectory(
            at: recordingsRoot,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)

        let link = recordingsRoot.appendingPathComponent("session", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        let reference = NotificationDirectoryReference(recordingsRoot: recordingsRoot)

        XCTAssertEqual(reference.token(for: link), "session")
        XCTAssertNil(reference.resolve("session"))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
    }
}
