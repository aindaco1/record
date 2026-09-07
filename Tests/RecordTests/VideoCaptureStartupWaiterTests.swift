import Foundation
@testable import Record
import RecordCore
import XCTest

final class VideoCaptureStartupWaiterTests: XCTestCase {
    func testPendingStopCannotPassStartupBeforeTheLastWriterHasMedia() async throws {
        let samples = StartupSamples()
        let readiness = CaptureStartupReadiness(audio: .init())
        try await VideoCaptureStartupWaiter.wait(
            isReady: { readiness.isReady(processedTracks: samples.tracks) },
            maximumPolls: 3,
            sleep: { samples.advance() }
        )
        XCTAssertEqual(samples.tracks, [.screen, .systemAudio, .microphone])
    }

    func testMissingWriterFailsWithinBoundInsteadOfPretendingToStart() async {
        do {
            try await VideoCaptureStartupWaiter.wait(
                isReady: { false }, maximumPolls: 2, sleep: {}
            )
            XCTFail("a missing writer must fail startup")
        } catch {
            XCTAssertEqual(
                error as? VideoRecordingSession.SessionError,
                .captureFailed(
                    .init(
                        code: .writerFailed,
                        summary: "one or more requested media tracks did not start")
                )
            )
        }
    }

    func testCancellationPropagatesToCaptureCleanup() async {
        do {
            try await VideoCaptureStartupWaiter.wait(
                isReady: { false }, sleep: { throw CancellationError() }
            )
            XCTFail("cancelled startup must stop waiting")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }
}

private final class StartupSamples: @unchecked Sendable {
    private let lock = NSLock()
    private var observed: Set<SessionManifest.TrackKind> = []
    var tracks: Set<SessionManifest.TrackKind> { lock.withLock { observed } }

    func advance() {
        lock.withLock {
            let order: [SessionManifest.TrackKind] = [.screen, .systemAudio, .microphone]
            if let next = order.first(where: { !observed.contains($0) }) {
                observed.insert(next)
            }
        }
    }
}
