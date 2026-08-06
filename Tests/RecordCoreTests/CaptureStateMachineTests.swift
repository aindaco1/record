import Foundation
import RecordCore
import XCTest

final class CaptureStateMachineTests: XCTestCase {
    func testCompletePauseResumeStopLifecycle() throws {
        let sessionID = UUID()
        let configuration = validConfiguration()
        var machine = CaptureStateMachine()

        XCTAssertEqual(
            try machine.handle(.start(sessionID: sessionID, configuration: configuration)),
            [.prepare(sessionID: sessionID, configuration: configuration)]
        )
        XCTAssertEqual(try machine.handle(.prepared), [.beginSegment(sessionID: sessionID)])
        XCTAssertEqual(try machine.handle(.pause), [.finishSegment(sessionID: sessionID)])
        XCTAssertEqual(machine.state, .paused(sessionID: sessionID))
        XCTAssertEqual(try machine.handle(.pause), [])
        XCTAssertEqual(try machine.handle(.resume), [.beginSegment(sessionID: sessionID)])
        XCTAssertEqual(
            try machine.handle(.stop),
            [.finishSegment(sessionID: sessionID), .finalizeSession(sessionID: sessionID)]
        )
        XCTAssertEqual(try machine.handle(.stop), [])
        XCTAssertEqual(try machine.handle(.stopped), [])
        XCTAssertEqual(machine.state, .idle)
    }

    func testStopDuringPreparationCancelsBeforeFinalizing() throws {
        let sessionID = UUID()
        var machine = CaptureStateMachine()
        try machine.handle(.start(sessionID: sessionID, configuration: validConfiguration()))

        XCTAssertEqual(
            try machine.handle(.stop),
            [
                .cancelPreparation(sessionID: sessionID),
                .finalizeSession(sessionID: sessionID),
            ]
        )
    }

    func testFailureAbortsOnceAndRequiresReset() throws {
        let sessionID = UUID()
        let failure = CaptureFailure(code: .writerFailed, summary: "media writer stopped")
        var machine = CaptureStateMachine()
        try machine.handle(.start(sessionID: sessionID, configuration: validConfiguration()))
        try machine.handle(.prepared)

        XCTAssertEqual(
            try machine.handle(.fail(failure)),
            [
                .abortSession(sessionID: sessionID),
                .recordFailure(sessionID: sessionID, failure: failure),
            ]
        )
        XCTAssertThrowsError(try machine.handle(.stop))
        XCTAssertEqual(try machine.handle(.reset), [])
        XCTAssertEqual(machine.state, .idle)
    }

    func testInvalidConfigurationDoesNotLeaveIdle() {
        var machine = CaptureStateMachine()
        let invalid = CaptureConfiguration(
            source: .display(id: 0),
            outputSize: .init(width: 1_920, height: 1_080)
        )

        XCTAssertThrowsError(try machine.handle(.start(sessionID: UUID(), configuration: invalid)))
        XCTAssertEqual(machine.state, .idle)
    }

    func testInvalidTransitionReportsCommandAndState() {
        var machine = CaptureStateMachine()

        XCTAssertThrowsError(try machine.handle(.resume)) { error in
            XCTAssertEqual(
                error as? CaptureStateMachine.StateMachineError,
                .invalidCommand(.resume, state: .idle)
            )
        }
    }

    private func validConfiguration() -> CaptureConfiguration {
        CaptureConfiguration(
            source: .display(id: 1),
            outputSize: .init(width: 1_920, height: 1_080)
        )
    }
}
