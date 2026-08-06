@testable import Record
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
}
