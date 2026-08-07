import Foundation
@testable import Record
import RecordCore
import XCTest

final class TranscriptionCoordinatorTests: XCTestCase {
    func testRejectsAJobWhenEveryAvailableTrackFailed() {
        XCTAssertThrowsError(
            try TranscriptionCoordinator.validateTrackResults(attempted: 2, succeeded: 0)
        ) { error in
            XCTAssertEqual(error as? PipelineError, .allTracksFailed(2))
        }
    }

    func testAcceptsSilenceWhenAnEngineSuccessfullyProcessedATrack() throws {
        XCTAssertNoThrow(
            try TranscriptionCoordinator.validateTrackResults(attempted: 2, succeeded: 1)
        )
    }

    func testAcceptsALegacySessionWithNoAvailableTracks() throws {
        XCTAssertNoThrow(
            try TranscriptionCoordinator.validateTrackResults(attempted: 0, succeeded: 0)
        )
    }

    func testRecoveryScanSkipsVideoOnlySessions() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "record-transcription-scan-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let video = root.appendingPathComponent("video", isDirectory: true)
        let audio = root.appendingPathComponent("audio", isDirectory: true)
        try FileManager.default.createDirectory(at: video, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: audio, withIntermediateDirectories: true)
        let startedAt = Date(timeIntervalSince1970: 1)
        let endedAt = Date(timeIntervalSince1970: 2)
        try SessionManifest(
            state: .finalized,
            startedAt: startedAt,
            endedAt: endedAt,
            tracks: [.init(kind: .screen, filename: "recording.mov")]
        ).write(to: video)
        try SessionManifest(
            state: .finalized,
            startedAt: startedAt,
            endedAt: endedAt,
            tracks: [.init(kind: .microphone, filename: "mic.caf", speaker: "me")]
        ).write(to: audio)

        let pending = TranscriptionCoordinator.pendingSessionDirectories(root: root)
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.lastPathComponent, "audio")
    }
}
