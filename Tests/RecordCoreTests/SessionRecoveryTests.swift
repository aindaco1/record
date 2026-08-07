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

    func testCompletedPauseSegmentMakesAnInterruptedSessionRecoverable() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let session = root.appendingPathComponent("paused", isDirectory: true)
        try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
        try SessionManifest(
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            tracks: [.init(kind: .screen, filename: "recording.mov")],
            captureSegments: [
                .init(
                    index: 1,
                    startedAtMilliseconds: 0,
                    endedAtMilliseconds: 5_000,
                    tracks: [.init(kind: .screen, filename: "segment-0001.mov")]
                )
            ],
            captureEvents: [
                .init(kind: .started, occurredAtMilliseconds: 0, segmentIndex: 1),
                .init(kind: .paused, occurredAtMilliseconds: 5_000, segmentIndex: 1),
            ]
        ).write(to: session)
        try Data([1, 2, 3]).write(to: session.appendingPathComponent("segment-0001.mov"))

        let report = SessionRecovery.recover(in: root, isProcessRunning: { _ in false })

        XCTAssertEqual(report.interrupted.map(\.lastPathComponent), ["paused"])
        XCTAssertEqual(try SessionManifest.read(from: session).state, .interrupted)
    }

    func testActiveSegmentPartialIsPromotedAndRecoveredThroughTheSegmentJournal() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let session = root.appendingPathComponent("rotating", isDirectory: true)
        try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
        try SessionManifest(
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            tracks: [.init(kind: .screen, filename: "recording.mov")],
            captureSegments: [
                .init(
                    index: 1,
                    startedAtMilliseconds: 0,
                    tracks: [.init(kind: .screen, filename: "segment-0001.mov")]
                )
            ],
            captureEvents: [
                .init(kind: .started, occurredAtMilliseconds: 0, segmentIndex: 1)
            ]
        ).write(to: session)
        let partial = session.appendingPathComponent(
            ".segment-0001.00000000-0000-0000-0000-000000000004.partial.mov"
        )
        try Data([4, 5, 6]).write(to: partial)

        let report = SessionRecovery.recover(
            in: root,
            isProcessRunning: { _ in false },
            inspectMedia: { _ in .playable },
            recoverPartialMedia: true
        )

        let promoted = session.appendingPathComponent("segment-0001.mov")
        XCTAssertEqual(
            report.promotedMedia.map { $0.resolvingSymlinksInPath() },
            [promoted.resolvingSymlinksInPath()]
        )
        XCTAssertEqual(
            report.interrupted.map { $0.resolvingSymlinksInPath() },
            [session.resolvingSymlinksInPath()]
        )
        XCTAssertEqual(try Data(contentsOf: promoted), Data([4, 5, 6]))
        XCTAssertEqual(try SessionManifest.read(from: session).state, .interrupted)
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

    func testPlayablePartialIsPromotedWithoutRewritingAndOnlyOnce() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let session = root.appendingPathComponent("partial", isDirectory: true)
        try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
        try SessionManifest(
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            tracks: [.init(kind: .microphone, filename: "mic.caf")]
        ).write(to: session)
        let partial = session.appendingPathComponent(
            ".mic.00000000-0000-0000-0000-000000000001.partial.caf"
        )
        let original = Data([1, 2, 3, 4])
        try original.write(to: partial)

        let first = SessionRecovery.recover(
            in: root,
            inspectMedia: { _ in .playable },
            recoverPartialMedia: true
        )
        let second = SessionRecovery.recover(
            in: root,
            inspectMedia: { _ in .playable },
            recoverPartialMedia: true
        )

        let promoted = session.appendingPathComponent("mic.caf")
        XCTAssertEqual(
            first.promotedMedia.map { $0.resolvingSymlinksInPath() },
            [promoted.resolvingSymlinksInPath()]
        )
        XCTAssertEqual(
            first.interrupted.map { $0.resolvingSymlinksInPath() },
            [session.resolvingSymlinksInPath()]
        )
        XCTAssertEqual(try Data(contentsOf: promoted), original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: partial.path))
        XCTAssertEqual(second, .init())
    }

    func testCorruptPartialIsQuarantinedWithoutDeletingBytes() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let session = root.appendingPathComponent("corrupt", isDirectory: true)
        try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
        try SessionManifest(
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            tracks: [.init(kind: .screen, filename: "recording.mov")]
        ).write(to: session)
        let partial = session.appendingPathComponent(
            ".recording.00000000-0000-0000-0000-000000000002.partial.mov"
        )
        let original = Data([0x62, 0x72, 0x6f, 0x6b, 0x65, 0x6e])
        try original.write(to: partial)

        let report = SessionRecovery.recover(
            in: root,
            inspectMedia: { _ in .corrupt },
            recoverPartialMedia: true
        )

        let quarantined = try XCTUnwrap(report.quarantinedMedia.first)
        XCTAssertEqual(
            report.failed.map { $0.resolvingSymlinksInPath() },
            [session.resolvingSymlinksInPath()]
        )
        XCTAssertEqual(report.corruptMedia, [quarantined])
        XCTAssertTrue(quarantined.path.contains("Recovery/Corrupt Media/"))
        XCTAssertEqual(try Data(contentsOf: quarantined), original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: partial.path))
        XCTAssertEqual(try SessionManifest.read(from: session).state, .failed)
    }

    func testUnrecognizedHiddenFileIsNeverMoved() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let session = root.appendingPathComponent("unrelated", isDirectory: true)
        try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
        try SessionManifest(startedAt: Date(), tracks: []).write(to: session)
        let unrelated = session.appendingPathComponent(".notes.partial.mov")
        try Data([1]).write(to: unrelated)

        let report = SessionRecovery.recover(
            in: root,
            inspectMedia: { _ in .playable },
            recoverPartialMedia: true
        )

        XCTAssertTrue(report.promotedMedia.isEmpty)
        XCTAssertTrue(report.quarantinedMedia.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
    }

    func testSymlinkedSessionAndPartialCannotEscapeRecoveryRoot() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let outside = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: outside) }
        try SessionManifest(startedAt: Date(), tracks: []).write(to: outside)
        let linkedSession = root.appendingPathComponent("linked-session")
        try FileManager.default.createSymbolicLink(at: linkedSession, withDestinationURL: outside)

        let session = root.appendingPathComponent("session", isDirectory: true)
        try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
        try SessionManifest(startedAt: Date(), tracks: []).write(to: session)
        let outsideMedia = outside.appendingPathComponent("outside.caf")
        try Data([1, 2, 3]).write(to: outsideMedia)
        let linkedPartial = session.appendingPathComponent(
            ".mic.00000000-0000-0000-0000-000000000003.partial.caf"
        )
        try FileManager.default.createSymbolicLink(
            at: linkedPartial,
            withDestinationURL: outsideMedia
        )

        let report = SessionRecovery.recover(
            in: root,
            inspectMedia: { _ in .playable },
            recoverPartialMedia: true
        )

        XCTAssertTrue(report.promotedMedia.isEmpty)
        XCTAssertTrue(report.quarantinedMedia.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: linkedPartial.path))
        XCTAssertEqual(try Data(contentsOf: outsideMedia), Data([1, 2, 3]))
        XCTAssertEqual(try SessionManifest.read(from: outside).state, .recording)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SessionRecoveryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
