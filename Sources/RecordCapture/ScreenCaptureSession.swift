import Foundation
import RecordCore

public protocol ScreenCaptureStreamDriving: Sendable {
    func startCapture() async throws
    func stopCapture() async throws
    func cancelCapture() async
}

/// Idempotent lifecycle wrapper around one prepared SCStream. The capture
/// state machine owns higher-level session and segment transitions.
public actor ScreenCaptureSession {
    public enum State: String, Equatable, Sendable {
        case prepared
        case starting
        case running
        case stopping
        case stopped
        case failed
    }

    public private(set) var state: State = .prepared

    private var driver: (any ScreenCaptureStreamDriving)?
    private var stopRequested = false
    private var driverNeedsStop = false
    private var stopWaiters: [CheckedContinuation<Void, any Error>] = []

    public init(driver: any ScreenCaptureStreamDriving) {
        self.driver = driver
    }

    public func start() async throws {
        switch state {
        case .prepared:
            state = .starting
        case .starting, .running:
            return
        case .stopping, .stopped, .failed:
            throw ScreenCaptureAdapterError.invalidState(state)
        }
        guard let driver else {
            state = .failed
            throw ScreenCaptureAdapterError.invalidState(state)
        }

        do {
            try await driver.startCapture()
            driverNeedsStop = true
        } catch {
            await driver.cancelCapture()
            self.driver = nil
            state = .failed
            let mapped = ScreenCaptureAdapterError.captureFailed(
                ScreenCaptureFailureMapper.failure(for: error)
            )
            resumeStopWaiters(with: .failure(mapped))
            throw mapped
        }

        if stopRequested {
            state = .stopping
            try await stopRunningDriver()
        } else {
            state = .running
        }
    }

    public func stop() async throws {
        switch state {
        case .prepared:
            state = .stopping
            await driver?.cancelCapture()
            driver = nil
            state = .stopped
            resumeStopWaiters(with: .success(()))
        case .starting:
            stopRequested = true
            try await waitForStop()
        case .running:
            state = .stopping
            try await stopRunningDriver()
        case .failed:
            if driverNeedsStop {
                state = .stopping
                try await stopRunningDriver()
            } else {
                driver = nil
                state = .stopped
                resumeStopWaiters(with: .success(()))
            }
        case .stopping:
            try await waitForStop()
        case .stopped:
            return
        }
    }

    private func stopRunningDriver() async throws {
        guard let driver else {
            state = .failed
            let error = ScreenCaptureAdapterError.invalidState(state)
            resumeStopWaiters(with: .failure(error))
            throw error
        }
        do {
            try await driver.stopCapture()
            driverNeedsStop = false
            self.driver = nil
            state = .stopped
            resumeStopWaiters(with: .success(()))
        } catch {
            await driver.cancelCapture()
            driverNeedsStop = false
            self.driver = nil
            state = .failed
            let mapped = ScreenCaptureAdapterError.captureFailed(
                ScreenCaptureFailureMapper.failure(for: error)
            )
            resumeStopWaiters(with: .failure(mapped))
            throw mapped
        }
    }

    private func waitForStop() async throws {
        try await withCheckedThrowingContinuation { continuation in
            stopWaiters.append(continuation)
        }
    }

    private func resumeStopWaiters(with result: Result<Void, any Error>) {
        let waiters = stopWaiters
        stopWaiters.removeAll(keepingCapacity: false)
        for waiter in waiters {
            waiter.resume(with: result)
        }
    }
}
