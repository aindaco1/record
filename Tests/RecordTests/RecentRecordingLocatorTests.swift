import Foundation
@testable import Record
import RecordCore
import XCTest

final class RecentRecordingLocatorTests: XCTestCase {
    func testFindsNewestFinishedSessionAcrossApprovedRoots() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.container) }

        let older = try makeSession(
            named: "older",
            under: fixture.privateRoot,
            state: .interrupted,
            endedAt: Date(timeIntervalSince1970: 20)
        )
        let newer = try makeSession(
            named: "newer",
            under: fixture.exportRoot,
            state: .finalized,
            endedAt: Date(timeIntervalSince1970: 30)
        )

        XCTAssertEqual(
            RecentRecordingLocator.mostRecent(
                under: [fixture.privateRoot, fixture.exportRoot]
            ),
            newer
        )
        XCTAssertTrue(
            RecentRecordingLocator.isFinishedSession(
                older,
                under: [fixture.privateRoot, fixture.exportRoot]
            )
        )
    }

    func testIgnoresRecordingFailedMalformedAndUnrelatedDirectories() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.container) }

        for (name, state) in [
            ("recording", SessionManifest.State.recording),
            ("failed", .failed),
        ] {
            _ = try makeSession(
                named: name,
                under: fixture.exportRoot,
                state: state,
                endedAt: state == .recording ? nil : Date(timeIntervalSince1970: 30)
            )
        }
        let malformed = fixture.exportRoot.appendingPathComponent(
            "malformed",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: malformed, withIntermediateDirectories: true)
        try Data("not-json".utf8).write(
            to: malformed.appendingPathComponent("session.json")
        )
        try FileManager.default.createDirectory(
            at: fixture.exportRoot.appendingPathComponent("unrelated", isDirectory: true),
            withIntermediateDirectories: true
        )

        XCTAssertNil(RecentRecordingLocator.mostRecent(under: [fixture.exportRoot]))
    }

    func testRejectsSymlinkAndNestedSessionEscapes() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.container) }

        let outside = try makeSession(
            named: "outside",
            under: fixture.container,
            state: .finalized,
            endedAt: Date(timeIntervalSince1970: 40)
        )
        let link = fixture.exportRoot.appendingPathComponent("linked", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        let nestedRoot = fixture.exportRoot.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedRoot, withIntermediateDirectories: true)
        let nested = try makeSession(
            named: "session",
            under: nestedRoot,
            state: .finalized,
            endedAt: Date(timeIntervalSince1970: 50)
        )

        XCTAssertNil(RecentRecordingLocator.mostRecent(under: [fixture.exportRoot]))
        XCTAssertFalse(
            RecentRecordingLocator.isFinishedSession(link, under: [fixture.exportRoot])
        )
        XCTAssertFalse(
            RecentRecordingLocator.isFinishedSession(nested, under: [fixture.exportRoot])
        )
    }

    func testRestoresLatestVideoIndependentlyOfLatestRecording() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.container) }

        let videoSession = try makeSession(
            named: "video",
            under: fixture.privateRoot,
            state: .finalized,
            endedAt: Date(timeIntervalSince1970: 20),
            tracks: [.init(kind: .screen, filename: "recording.mov")]
        )
        let video = videoSession.appendingPathComponent("recording.mov")
        try Data("video".utf8).write(to: video)
        let audioSession = try makeSession(
            named: "audio",
            under: fixture.exportRoot,
            state: .finalized,
            endedAt: Date(timeIntervalSince1970: 30)
        )

        XCTAssertEqual(
            RecentRecordingLocator.snapshot(
                under: [fixture.privateRoot, fixture.exportRoot]
            ),
            .init(recordingDirectory: audioSession, videoURL: video)
        )
    }

    func testRejectsMissingEmptyAndSymlinkedVideos() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.container) }

        _ = try makeSession(
            named: "missing",
            under: fixture.exportRoot,
            state: .finalized,
            endedAt: Date(timeIntervalSince1970: 20),
            tracks: [.init(kind: .screen, filename: "recording.mov")]
        )
        let empty = try makeSession(
            named: "empty",
            under: fixture.exportRoot,
            state: .finalized,
            endedAt: Date(timeIntervalSince1970: 30),
            tracks: [.init(kind: .screen, filename: "recording.mov")]
        )
        XCTAssertTrue(
            FileManager.default.createFile(
                atPath: empty.appendingPathComponent("recording.mov").path,
                contents: Data()
            )
        )
        let linked = try makeSession(
            named: "linked",
            under: fixture.exportRoot,
            state: .finalized,
            endedAt: Date(timeIntervalSince1970: 40),
            tracks: [.init(kind: .screen, filename: "recording.mov")]
        )
        let outside = fixture.container.appendingPathComponent("outside.mov")
        try Data("outside".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(
            at: linked.appendingPathComponent("recording.mov"),
            withDestinationURL: outside
        )

        let snapshot = RecentRecordingLocator.snapshot(under: [fixture.exportRoot])
        XCTAssertEqual(snapshot.recordingDirectory, linked)
        XCTAssertNil(snapshot.videoURL)
    }

    func testRecoveryMaterialAppearsForAPrivateSessionManifest() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.container) }

        XCTAssertFalse(RecoveryMaterialLocator.hasMaterial(under: fixture.privateRoot))
        _ = try makeSession(
            named: "failed-export",
            under: fixture.privateRoot,
            state: .finalized,
            endedAt: Date(timeIntervalSince1970: 30)
        )
        XCTAssertTrue(RecoveryMaterialLocator.hasMaterial(under: fixture.privateRoot))
    }

    func testRecoveryMaterialRejectsUnrelatedNestedAndSymlinkedDirectories() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.container) }

        try FileManager.default.createDirectory(
            at: fixture.privateRoot.appendingPathComponent("unrelated", isDirectory: true),
            withIntermediateDirectories: true
        )
        let nestedRoot = fixture.privateRoot.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedRoot, withIntermediateDirectories: true)
        _ = try makeSession(
            named: "session",
            under: nestedRoot,
            state: .interrupted,
            endedAt: Date(timeIntervalSince1970: 30)
        )
        let outside = try makeSession(
            named: "outside",
            under: fixture.container,
            state: .failed,
            endedAt: Date(timeIntervalSince1970: 30)
        )
        try FileManager.default.createSymbolicLink(
            at: fixture.privateRoot.appendingPathComponent("linked", isDirectory: true),
            withDestinationURL: outside
        )
        let linkedManifest = fixture.privateRoot.appendingPathComponent(
            "linked-manifest",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: linkedManifest,
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(
            at: linkedManifest.appendingPathComponent("session.json"),
            withDestinationURL: outside.appendingPathComponent("session.json")
        )

        XCTAssertFalse(RecoveryMaterialLocator.hasMaterial(under: fixture.privateRoot))
    }

    private func makeFixture() throws -> (
        container: URL,
        privateRoot: URL,
        exportRoot: URL
    ) {
        let container = FileManager.default.temporaryDirectory.appendingPathComponent(
            "record-recent-locator-\(UUID().uuidString)",
            isDirectory: true
        )
        let privateRoot = container.appendingPathComponent("private", isDirectory: true)
        let exportRoot = container.appendingPathComponent("exports", isDirectory: true)
        try FileManager.default.createDirectory(
            at: privateRoot,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: exportRoot,
            withIntermediateDirectories: true
        )
        return (container, privateRoot, exportRoot)
    }

    private func makeSession(
        named name: String,
        under root: URL,
        state: SessionManifest.State,
        endedAt: Date?,
        tracks: [SessionManifest.Track] = [
            .init(kind: .microphone, filename: "mic.caf")
        ]
    ) throws -> URL {
        let directory = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try SessionManifest(
            state: state,
            startedAt: Date(timeIntervalSince1970: 10),
            endedAt: endedAt,
            tracks: tracks
        ).write(to: directory)
        return directory
    }
}
