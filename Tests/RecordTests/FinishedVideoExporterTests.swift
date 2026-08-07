import Foundation
@testable import Record
import XCTest

final class FinishedVideoExporterTests: XCTestCase {
    func testExportCopiesAtomicallyAndNeverOverwrites() throws {
        let fixture = try makeFixture(sourceData: Data("video".utf8))
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let first = try FinishedVideoExporter.export(
            sourceURL: fixture.source,
            to: fixture.destination,
            preferredBaseName: "Record Test"
        )
        let second = try FinishedVideoExporter.export(
            sourceURL: fixture.source,
            to: fixture.destination,
            preferredBaseName: "Record Test"
        )

        XCTAssertNotEqual(first, second)
        XCTAssertEqual(try Data(contentsOf: first), Data("video".utf8))
        XCTAssertEqual(try Data(contentsOf: second), Data("video".utf8))
        let names = try FileManager.default.contentsOfDirectory(
            atPath: fixture.destination.path
        )
        XCTAssertFalse(names.contains { $0.hasPrefix(".") || $0.contains("partial") })
    }

    func testExportRejectsAnEmptySource() throws {
        let fixture = try makeFixture(sourceData: Data())
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        XCTAssertThrowsError(
            try FinishedVideoExporter.export(
                sourceURL: fixture.source,
                to: fixture.destination,
                preferredBaseName: "Record Test"
            )
        ) { error in
            XCTAssertEqual(error as? FinishedVideoExporter.ExportError, .invalidSource)
        }
    }

    func testExportRejectsAnUnsafeName() throws {
        let fixture = try makeFixture(sourceData: Data("video".utf8))
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        XCTAssertThrowsError(
            try FinishedVideoExporter.export(
                sourceURL: fixture.source,
                to: fixture.destination,
                preferredBaseName: "../private"
            )
        ) { error in
            XCTAssertEqual(error as? FinishedVideoExporter.ExportError, .invalidName)
        }
    }

    func testExportRejectsANameOverTheUTF8ByteLimit() throws {
        let fixture = try makeFixture(sourceData: Data("video".utf8))
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        XCTAssertThrowsError(
            try FinishedVideoExporter.export(
                sourceURL: fixture.source,
                to: fixture.destination,
                preferredBaseName: String(repeating: "🙂", count: 51)
            )
        ) { error in
            XCTAssertEqual(error as? FinishedVideoExporter.ExportError, .invalidName)
        }
    }

    private func makeFixture(sourceData: Data) throws -> (
        root: URL,
        source: URL,
        destination: URL
    ) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "record-video-export-\(UUID().uuidString)",
            isDirectory: true
        )
        let sourceDirectory = root.appendingPathComponent("source", isDirectory: true)
        let destination = root.appendingPathComponent("destination", isDirectory: true)
        try FileManager.default.createDirectory(
            at: sourceDirectory,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: destination,
            withIntermediateDirectories: true
        )
        let source = sourceDirectory.appendingPathComponent("recording.mov")
        try sourceData.write(to: source)
        return (root, source, destination)
    }
}
