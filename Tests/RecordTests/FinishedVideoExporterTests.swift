import Foundation
@testable import Record
import RecordCore
import XCTest

final class FinishedSessionExporterTests: XCTestCase {
    func testExportCopiesWholeSessionAtomicallyAndNeverOverwrites() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let first = try FinishedSessionExporter.export(
            sourceDirectory: fixture.source,
            to: fixture.destination,
            preferredDirectoryName: "Record Test"
        )
        let second = try FinishedSessionExporter.export(
            sourceDirectory: fixture.source,
            to: fixture.destination,
            preferredDirectoryName: "Record Test"
        )

        XCTAssertNotEqual(first.directoryURL, second.directoryURL)
        XCTAssertEqual(first.videoURL.lastPathComponent, "recording.mov")
        for export in [first, second] {
            XCTAssertEqual(
                Set(try FileManager.default.contentsOfDirectory(atPath: export.directoryURL.path)),
                ["session.json", "recording.mov", "system.caf", "mic.caf"]
            )
            XCTAssertEqual(try Data(contentsOf: export.videoURL), Data("video".utf8))
            XCTAssertEqual(try SessionManifest.read(from: export.directoryURL).state, .finalized)
        }
        let names = try FileManager.default.contentsOfDirectory(
            atPath: fixture.destination.path
        )
        XCTAssertFalse(names.contains { $0.hasPrefix(".") || $0.contains("partial") })
    }

    func testExportRejectsMissingOrEmptyDeclaredTrack() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try FileManager.default.removeItem(
            at: fixture.source.appendingPathComponent("mic.caf")
        )

        XCTAssertThrowsError(
            try FinishedSessionExporter.export(
                sourceDirectory: fixture.source,
                to: fixture.destination,
                preferredDirectoryName: "Record Test"
            )
        ) { error in
            XCTAssertEqual(error as? FinishedSessionExporter.ExportError, .invalidSource)
        }
    }

    func testExportRejectsUnfinalizedSession() throws {
        let fixture = try makeFixture(state: .failed)
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        XCTAssertThrowsError(
            try FinishedSessionExporter.export(
                sourceDirectory: fixture.source,
                to: fixture.destination,
                preferredDirectoryName: "Record Test"
            )
        ) { error in
            XCTAssertEqual(error as? FinishedSessionExporter.ExportError, .invalidSource)
        }
    }

    func testExportRejectsUnsafeName() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        for name in ["../private", ".", String(repeating: "🙂", count: 51)] {
            XCTAssertThrowsError(
                try FinishedSessionExporter.export(
                    sourceDirectory: fixture.source,
                    to: fixture.destination,
                    preferredDirectoryName: name
                )
            ) { error in
                XCTAssertEqual(error as? FinishedSessionExporter.ExportError, .invalidName)
            }
        }
    }

    func testCleanupRemovesOnlyFinalizedDirectChild() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        try PrivateSessionCleaner.removeFinalizedSession(
            fixture.source,
            under: fixture.recordingsRoot
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.source.path))
    }

    func testCleanupRejectsOutsideNestedAndUnfinalizedDirectories() throws {
        let fixture = try makeFixture(state: .failed)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let nested = fixture.source.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)

        XCTAssertThrowsError(
            try PrivateSessionCleaner.removeFinalizedSession(
                fixture.source,
                under: fixture.recordingsRoot
            )
        ) { error in
            XCTAssertEqual(error as? PrivateSessionCleaner.CleanupError, .sessionNotFinalized)
        }
        XCTAssertThrowsError(
            try PrivateSessionCleaner.removeFinalizedSession(
                nested,
                under: fixture.recordingsRoot
            )
        ) { error in
            XCTAssertEqual(error as? PrivateSessionCleaner.CleanupError, .unsafeDirectory)
        }
        XCTAssertThrowsError(
            try PrivateSessionCleaner.removeFinalizedSession(
                fixture.destination,
                under: fixture.recordingsRoot
            )
        ) { error in
            XCTAssertEqual(error as? PrivateSessionCleaner.CleanupError, .unsafeDirectory)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.source.path))
    }

    private func makeFixture(
        state: SessionManifest.State = .finalized
    ) throws -> (
        root: URL,
        recordingsRoot: URL,
        source: URL,
        destination: URL
    ) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "record-session-export-\(UUID().uuidString)",
            isDirectory: true
        )
        let recordingsRoot = root.appendingPathComponent("Recordings", isDirectory: true)
        let source = recordingsRoot.appendingPathComponent("source", isDirectory: true)
        let destination = root.appendingPathComponent("Desktop", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: destination,
            withIntermediateDirectories: true
        )
        try Data("video".utf8).write(to: source.appendingPathComponent("recording.mov"))
        try Data("system".utf8).write(to: source.appendingPathComponent("system.caf"))
        try Data("microphone".utf8).write(to: source.appendingPathComponent("mic.caf"))
        let start = Date(timeIntervalSince1970: 100)
        try SessionManifest(
            state: state,
            startedAt: start,
            endedAt: start.addingTimeInterval(10),
            tracks: [
                .init(kind: .screen, filename: "recording.mov"),
                .init(kind: .systemAudio, filename: "system.caf", speaker: "them"),
                .init(kind: .microphone, filename: "mic.caf", speaker: "me"),
            ]
        ).write(to: source)
        return (root, recordingsRoot, source, destination)
    }
}
