import Foundation

public struct CaptureFailure: Codable, Equatable, Sendable {
    public enum Code: String, Codable, Sendable {
        case permissionDenied
        case sourceUnavailable
        case encoderFailed
        case writerFailed
        case deviceDisconnected
        case internalFailure
    }

    public let code: Code
    public let summary: String

    public init(code: Code, summary: String) {
        self.code = code
        self.summary = summary
    }
}

/// Pure capture lifecycle. The owning actor executes returned effects and
/// feeds completion/failure commands back into this state machine.
public struct CaptureStateMachine: Sendable {
    public enum State: Equatable, Sendable {
        case idle
        case preparing(sessionID: UUID)
        case recording(sessionID: UUID)
        case paused(sessionID: UUID)
        case stopping(sessionID: UUID)
        case failed(sessionID: UUID?, failure: CaptureFailure)
    }

    public enum Command: Equatable, Sendable {
        case start(sessionID: UUID, configuration: CaptureConfiguration)
        case prepared
        case pause
        case resume
        case stop
        case stopped
        case fail(CaptureFailure)
        case reset
    }

    public enum Effect: Equatable, Sendable {
        case prepare(sessionID: UUID, configuration: CaptureConfiguration)
        case beginSegment(sessionID: UUID)
        case finishSegment(sessionID: UUID)
        case cancelPreparation(sessionID: UUID)
        case finalizeSession(sessionID: UUID)
        case abortSession(sessionID: UUID)
        case recordFailure(sessionID: UUID?, failure: CaptureFailure)
    }

    public enum StateMachineError: Error, Equatable {
        case invalidConfiguration(CaptureConfiguration.ValidationError)
        case invalidCommand(Command, state: State)
    }

    public private(set) var state: State = .idle

    public init() {}

    @discardableResult
    public mutating func handle(_ command: Command) throws -> [Effect] {
        switch (state, command) {
        case (.idle, .start(let sessionID, let configuration)):
            do {
                try configuration.validate()
            } catch let error as CaptureConfiguration.ValidationError {
                throw StateMachineError.invalidConfiguration(error)
            }
            state = .preparing(sessionID: sessionID)
            return [.prepare(sessionID: sessionID, configuration: configuration)]

        case (.preparing(let sessionID), .prepared):
            state = .recording(sessionID: sessionID)
            return [.beginSegment(sessionID: sessionID)]

        case (.recording(let sessionID), .pause):
            state = .paused(sessionID: sessionID)
            return [.finishSegment(sessionID: sessionID)]

        case (.paused, .pause), (.recording, .resume), (.stopping, .stop):
            return []

        case (.paused(let sessionID), .resume):
            state = .recording(sessionID: sessionID)
            return [.beginSegment(sessionID: sessionID)]

        case (.preparing(let sessionID), .stop):
            state = .stopping(sessionID: sessionID)
            return [
                .cancelPreparation(sessionID: sessionID),
                .finalizeSession(sessionID: sessionID),
            ]

        case (.recording(let sessionID), .stop):
            state = .stopping(sessionID: sessionID)
            return [
                .finishSegment(sessionID: sessionID),
                .finalizeSession(sessionID: sessionID),
            ]

        case (.paused(let sessionID), .stop):
            state = .stopping(sessionID: sessionID)
            return [.finalizeSession(sessionID: sessionID)]

        case (.stopping, .stopped):
            state = .idle
            return []

        case (.preparing(let sessionID), .fail(let failure)),
            (.recording(let sessionID), .fail(let failure)),
            (.paused(let sessionID), .fail(let failure)),
            (.stopping(let sessionID), .fail(let failure)):
            state = .failed(sessionID: sessionID, failure: failure)
            return [
                .abortSession(sessionID: sessionID),
                .recordFailure(sessionID: sessionID, failure: failure),
            ]

        case (.idle, .fail(let failure)):
            state = .failed(sessionID: nil, failure: failure)
            return [.recordFailure(sessionID: nil, failure: failure)]

        case (.failed, .reset):
            state = .idle
            return []

        case (.idle, .reset):
            return []

        default:
            throw StateMachineError.invalidCommand(command, state: state)
        }
    }
}
