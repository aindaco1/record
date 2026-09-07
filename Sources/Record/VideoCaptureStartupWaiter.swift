import Foundation
import RecordCore

/// Wait outside the capture callbacks and media worker. A pending Stop remains
/// serialized behind startup, with a five-second bound for a missing track.
enum VideoCaptureStartupWaiter {
    static func wait(
        isReady: @Sendable () -> Bool,
        maximumPolls: Int = 500,
        sleep: @Sendable () async throws -> Void = {
            try await Task.sleep(for: .milliseconds(10))
        }
    ) async throws {
        for _ in 0..<maximumPolls {
            try Task.checkCancellation()
            if isReady() { return }
            try await sleep()
        }
        try Task.checkCancellation()
        guard isReady() else {
            throw VideoRecordingSession.SessionError.captureFailed(
                CaptureFailure(
                    code: .writerFailed,
                    summary: "one or more requested media tracks did not start"
                )
            )
        }
    }
}
