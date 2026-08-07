import Foundation

/// Content-free diagnostics for a capture track. These events describe only
/// transport health; they never include filenames, device names, or samples.
public struct CaptureHealthEvent: Codable, Equatable, Sendable {
    public enum Track: String, Codable, Sendable {
        case screen
        case systemAudio = "system_audio"
        case microphone
    }

    public enum Code: String, Codable, Sendable {
        case routeChanged = "route_changed"
        case routeRecovered = "route_recovered"
        case routeRecoveryFailed = "route_recovery_failed"
        case voiceProcessingFallback = "voice_processing_fallback"
        case missingCallbacks = "missing_callbacks"
        case digitalSilence = "digital_silence"
        case queuePressure = "queue_pressure"
        case writeFailed = "write_failed"
    }

    public enum Severity: String, Codable, Sendable {
        case information
        case degraded
        case failed
    }

    public let track: Track
    public let code: Code
    public let severity: Severity
    public let occurredAtMilliseconds: Int
    public let durationMilliseconds: Int?

    public init(
        track: Track,
        code: Code,
        severity: Severity,
        occurredAtMilliseconds: Int,
        durationMilliseconds: Int? = nil
    ) {
        self.track = track
        self.code = code
        self.severity = severity
        self.occurredAtMilliseconds = max(0, occurredAtMilliseconds)
        self.durationMilliseconds = durationMilliseconds.map { max(0, $0) }
    }

    enum CodingKeys: String, CodingKey {
        case track
        case code
        case severity
        case occurredAtMilliseconds = "occurred_at_ms"
        case durationMilliseconds = "duration_ms"
    }
}

/// Distinguishes a healthy post-route restart from an AVAudioEngine
/// configuration-notification loop. The engine may emit a delayed
/// configuration event for the graph Record just created. Defer that event
/// briefly, then require a recent callback; a silent VoiceProcessingIO graph
/// falls back once to the raw input path instead of restarting forever.
public struct MicrophoneRestartLivenessGuard: Sendable {
    public enum Decision: Equatable, Sendable {
        case healthy
        case fallBackToRaw
        case retryCapture
    }

    public static let stabilizationMilliseconds = 2_000
    public static let recentCallbackToleranceMilliseconds = 250

    private struct Watch: Sendable {
        let startedAtMilliseconds: Int
        let voiceProcessingEnabled: Bool
    }

    private var watch: Watch?

    public init() {}

    public mutating func begin(
        atMilliseconds: Int,
        voiceProcessingEnabled: Bool
    ) {
        watch = Watch(
            startedAtMilliseconds: max(0, atMilliseconds),
            voiceProcessingEnabled: voiceProcessingEnabled
        )
    }

    public func shouldDeferEngineConfigurationChange(atMilliseconds: Int) -> Bool {
        guard let watch else { return false }
        let elapsed = max(0, atMilliseconds) - watch.startedAtMilliseconds
        return elapsed >= 0 && elapsed <= Self.stabilizationMilliseconds
    }

    public mutating func evaluate(
        atMilliseconds: Int,
        lastCallbackAtMilliseconds: Int?,
        captureIsRunning: Bool
    ) -> Decision? {
        guard let watch else { return nil }
        self.watch = nil

        let evaluatedAt = max(watch.startedAtMilliseconds, atMilliseconds)
        let callbackIsRecent =
            lastCallbackAtMilliseconds.map { callbackAt in
                callbackAt >= watch.startedAtMilliseconds
                    && callbackAt <= evaluatedAt
                    && evaluatedAt - callbackAt <= Self.recentCallbackToleranceMilliseconds
            } ?? false
        if callbackIsRecent && captureIsRunning { return .healthy }
        return watch.voiceProcessingEnabled ? .fallBackToRaw : .retryCapture
    }

    public mutating func cancel() {
        watch = nil
    }
}

/// Pure transition policy for microphone route changes. Framework callbacks
/// feed events into this type; the owning capture queue executes its effects.
public struct MicrophoneRouteRecoveryStateMachine: Sendable {
    public enum State: Equatable, Sendable {
        case idle
        case recording
        case restartScheduled(changeAtMilliseconds: Int)
        case restarting(changeAtMilliseconds: Int)
        case retryScheduled(changeAtMilliseconds: Int)
        case stopped
    }

    public enum Event: Equatable, Sendable {
        case start
        case routeChanged(atMilliseconds: Int)
        case restartDelayElapsed(atMilliseconds: Int)
        case restartSucceeded(atMilliseconds: Int)
        case restartFailed(atMilliseconds: Int)
        case retryDelayElapsed(atMilliseconds: Int)
        case stop
    }

    public enum Effect: Equatable, Sendable {
        case scheduleRestart(milliseconds: Int)
        case restartCapture
        case scheduleRetry(milliseconds: Int)
        case record(CaptureHealthEvent)
    }

    public static let restartDebounceMilliseconds = 500
    public static let retryDelayMilliseconds = 2_000

    public private(set) var state: State = .idle

    public init() {}

    @discardableResult
    public mutating func handle(_ event: Event) -> [Effect] {
        switch (state, event) {
        case (.idle, .start):
            state = .recording
            return []

        case (.recording, .routeChanged(let at)),
            (.restartScheduled, .routeChanged(let at)):
            let timestamp = max(0, at)
            state = .restartScheduled(changeAtMilliseconds: timestamp)
            return [.scheduleRestart(milliseconds: Self.restartDebounceMilliseconds)]

        case (.restartScheduled(let changedAt), .restartDelayElapsed):
            state = .restarting(changeAtMilliseconds: changedAt)
            return [
                .record(
                    .init(
                        track: .microphone,
                        code: .routeChanged,
                        severity: .information,
                        occurredAtMilliseconds: changedAt
                    )
                ),
                .restartCapture,
            ]

        case (.restarting(let changedAt), .restartSucceeded(let at)):
            let recoveredAt = max(changedAt, at)
            state = .recording
            return [
                .record(
                    .init(
                        track: .microphone,
                        code: .routeRecovered,
                        severity: .information,
                        occurredAtMilliseconds: recoveredAt,
                        durationMilliseconds: recoveredAt - changedAt
                    )
                )
            ]

        case (.restarting(let changedAt), .restartFailed(let at)):
            let failedAt = max(changedAt, at)
            state = .retryScheduled(changeAtMilliseconds: changedAt)
            return [
                .record(
                    .init(
                        track: .microphone,
                        code: .routeRecoveryFailed,
                        severity: .degraded,
                        occurredAtMilliseconds: failedAt,
                        durationMilliseconds: failedAt - changedAt
                    )
                ),
                .scheduleRetry(milliseconds: Self.retryDelayMilliseconds),
            ]

        case (.retryScheduled(let changedAt), .retryDelayElapsed):
            state = .restarting(changeAtMilliseconds: changedAt)
            return [.restartCapture]

        case (.idle, .stop), (.stopped, .stop):
            state = .stopped
            return []

        case (.recording, .stop), (.restartScheduled, .stop), (.restarting, .stop),
            (.retryScheduled, .stop):
            state = .stopped
            return []

        case (.stopped, _):
            return []

        default:
            return []
        }
    }
}
