import Foundation
import RecordCore
import XCTest

final class SessionRecoveryTests: XCTestCase {
    func testPreservedMediaTransitionsToInterruptedAndIsIdempotent() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let session = root.appendingPathComponent("session", isDirectory: true)
        try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
        let started = Date(timeIntervalSince1970: 1_700_000_000)
        let recoveredAt = started.addingTimeInterval(60)
        let manifest = SessionManifest(
            startedAt: started,
            tracks: [.init(kind: .microphone, filename: "mic.caf")]
        )
        try manifest.write(to: session)
        try Data([0x01, 0x02]).write(to: session.appendingPathComponent("mic.caf"))

        let first = SessionRecovery.recover(in: root, at: recoveredAt)
        let second = SessionRecovery.recover(in: root, at: recoveredAt.addingTimeInterval(1))

        XCTAssertEqual(first.interrupted.map(\.lastPathComponent), ["session"])
        XCTAssertTrue(first.failed.isEmpty)
        XCTAssertTrue(first.errors.isEmpty)
        XCTAssertEqual(try SessionManifest.read(from: session).state, .interrupted)
        XCTAssertEqual(try SessionManifest.read(from: session).endedAt, recoveredAt)
        XCTAssertEqual(
            try Data(contentsOf: session.appendingPathComponent("mic.caf")), Data([1, 2]))
        XCTAssertEqual(second, .init())
    }

    func testEmptySessionTransitionsToFailedWithoutDeletingDirectory() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let session = root.appendingPathComponent("empty", isDirectory: true)
        try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
        let manifest = SessionManifest(
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            tracks: [.init(kind: .systemAudio, filename: "system.caf")]
        )
        try manifest.write(to: session)

        let report = SessionRecovery.recover(in: root)

        XCTAssertEqual(report.failed.map(\.lastPathComponent), ["empty"])
        XCTAssertEqual(try SessionManifest.read(from: session).state, .failed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: session.path))
    }

    func testLiveOwnerIsNeverRecovered() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let session = root.appendingPathComponent("live", isDirectory: true)
        try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
        let manifest = SessionManifest(
            ownerProcessIdentifier: 42,
            startedAt: Date(),
            tracks: [.init(kind: .microphone, filename: "mic.caf")]
        )
        try manifest.write(to: session)

        let report = SessionRecovery.recover(in: root, isProcessRunning: { $0 == 42 })

        XCTAssertEqual(report, .init())
        XCTAssertEqual(try SessionManifest.read(from: session).state, .recording)
    }

    func testMalformedManifestIsReportedAndLeftUntouched() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let session = root.appendingPathComponent("malformed", isDirectory: true)
        try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
        let original = Data("not-json".utf8)
        let manifestURL = session.appendingPathComponent("session.json")
        try original.write(to: manifestURL)

        let report = SessionRecovery.recover(in: root)

        XCTAssertEqual(report.errors.count, 1)
        XCTAssertEqual(report.errors.first?.directory.lastPathComponent, "malformed")
        XCTAssertEqual(try Data(contentsOf: manifestURL), original)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SessionRecoveryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
