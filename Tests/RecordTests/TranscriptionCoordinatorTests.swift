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

    func testRecoveryNotificationSummarizesWithoutExposingSessionContent() throws {
        let root = URL(fileURLWithPath: "/tmp/record-recovery", isDirectory: true)
        let report = SessionRecovery.Report(
            interrupted: [root.appendingPathComponent("one")],
            failed: [root.appendingPathComponent("two")],
            errors: [
                .init(
                    directory: root.appendingPathComponent("three"),
                    description: "malformed"
                )
            ]
        )

        let notification = try XCTUnwrap(
            TranscriptionCoordinator.recoveryNotification(for: report, root: root)
        )

        XCTAssertEqual(notification.title, "Recording recovery finished")
        XCTAssertEqual(notification.destinationDirectory, root)
        XCTAssertEqual(
            notification.body,
            "Record preserved 1 interrupted recording, marked 1 empty session as failed, "
                + "found 1 session needing manual review. Click to open temp sessions."
        )
        XCTAssertFalse(notification.body.contains("one"))
        XCTAssertFalse(notification.body.contains("malformed"))
    }

    func testEmptyRecoveryDoesNotNotify() {
        XCTAssertNil(
            TranscriptionCoordinator.recoveryNotification(
                for: .init(),
                root: URL(fileURLWithPath: "/tmp/record-recovery", isDirectory: true)
            )
        )
    }

    func testRetryWithoutAFailedJobIsANoOp() async {
        let coordinator = TranscriptionCoordinator()
        let retried = await coordinator.retryLastFailure()
        XCTAssertFalse(retried)
    }

    func testRetryStateReturnsTheLatestFailureOnlyOnce() {
        var state = TranscriptionRetryState()
        let earlier = URL(fileURLWithPath: "/tmp/record-retry/earlier")
        let latest = URL(fileURLWithPath: "/tmp/record-retry/one/../latest")

        state.recordFailure(in: earlier)
        state.recordFailure(in: latest)

        XCTAssertEqual(state.failedDirectory, latest.standardizedFileURL)
        XCTAssertEqual(state.takeFailure(), latest.standardizedFileURL)
        XCTAssertNil(state.takeFailure())
    }

    func testClearingRetryStateRemovesTheFailure() {
        var state = TranscriptionRetryState()
        state.recordFailure(in: URL(fileURLWithPath: "/tmp/record-retry/failed"))

        state.clear()

        XCTAssertNil(state.failedDirectory)
    }

    func testCompletionHookClaimIsAtMostOnceAcrossRecoveryAttempts() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "CompletionHookClaimTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        XCTAssertTrue(TranscriptionCoordinator.claimCompletionHook(in: directory))
        XCTAssertFalse(TranscriptionCoordinator.claimCompletionHook(in: directory))
    }
}
