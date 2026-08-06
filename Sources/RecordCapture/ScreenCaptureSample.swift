import CoreMedia
import Foundation
import RecordCore
import ScreenCaptureKit

public enum ScreenCaptureSampleKind: String, CaseIterable, Hashable, Sendable {
    case screen
    case systemAudio
    case microphone
}

public struct ScreenCaptureTimestamp: Equatable, Sendable {
    public let time: CMTime

    public init(validating time: CMTime) throws {
        guard time.isValid, time.isNumeric, time.timescale > 0 else {
            throw TimestampError.invalid(time)
        }
        self.time = time
    }

    public enum TimestampError: Error, Equatable {
        case invalid(CMTime)
        case nonMonotonic(
            kind: ScreenCaptureSampleKind,
            previous: ScreenCaptureTimestamp,
            current: ScreenCaptureTimestamp
        )
    }
}

/// Validates monotonicity independently for each ScreenCaptureKit output.
/// Raw presentation timestamps stay untouched so the media writer can choose
/// one shared session anchor without losing A/V clock information.
public struct ScreenCaptureTimestampTracker: Sendable {
    private var latest: [ScreenCaptureSampleKind: ScreenCaptureTimestamp] = [:]

    public init() {}

    @discardableResult
    public mutating func observe(
        _ time: CMTime,
        kind: ScreenCaptureSampleKind
    ) throws -> ScreenCaptureTimestamp {
        let timestamp = try ScreenCaptureTimestamp(validating: time)
        if let previous = latest[kind], CMTimeCompare(time, previous.time) < 0 {
            throw ScreenCaptureTimestamp.TimestampError.nonMonotonic(
                kind: kind,
                previous: previous,
                current: timestamp
            )
        }
        latest[kind] = timestamp
        return timestamp
    }
}

public struct ScreenCaptureSample: @unchecked Sendable {
    public let kind: ScreenCaptureSampleKind
    public let timestamp: ScreenCaptureTimestamp
    public let buffer: CMSampleBuffer

    public init(
        kind: ScreenCaptureSampleKind,
        timestamp: ScreenCaptureTimestamp,
        buffer: CMSampleBuffer
    ) {
        self.kind = kind
        self.timestamp = timestamp
        self.buffer = buffer
    }
}

/// Implementations must enqueue or consume synchronously without blocking the
/// ScreenCaptureKit callback queue. Buffering belongs in a bounded media queue.
public protocol ScreenCaptureSampleSink: AnyObject, Sendable {
    func consume(_ sample: ScreenCaptureSample)
}

public enum ScreenCaptureEvent: Equatable, Sendable {
    /// The person used macOS's native stop-sharing control.
    case stopRequested
    case failed(CaptureFailure)
}

public enum ScreenCaptureFailureMapper {
    public static func event(for error: Error) -> ScreenCaptureEvent {
        let nsError = error as NSError
        if nsError.domain == SCStreamErrorDomain,
            nsError.code == SCStreamError.Code.userStopped.rawValue
        {
            return .stopRequested
        }
        return .failed(failure(for: error))
    }

    public static func failure(for error: Error) -> CaptureFailure {
        let nsError = error as NSError
        guard nsError.domain == SCStreamErrorDomain,
            let code = SCStreamError.Code(rawValue: nsError.code)
        else {
            return CaptureFailure(
                code: .internalFailure,
                summary: "screen capture stopped unexpectedly"
            )
        }

        switch code {
        case .userDeclined, .missingEntitlements:
            return CaptureFailure(
                code: .permissionDenied,
                summary: "screen recording permission was denied"
            )

        case .failedApplicationConnectionInvalid,
            .failedApplicationConnectionInterrupted,
            .failedNoMatchingApplicationContext,
            .noWindowList,
            .noDisplayList,
            .noCaptureSource,
            .systemStoppedStream:
            return CaptureFailure(
                code: .sourceUnavailable,
                summary: "the selected capture source is no longer available"
            )

        case .failedToStartAudioCapture,
            .failedToStopAudioCapture,
            .failedToStartMicrophoneCapture:
            return CaptureFailure(
                code: .deviceDisconnected,
                summary: "an audio capture device failed"
            )

        case .userStopped:
            return CaptureFailure(
                code: .internalFailure,
                summary: "screen capture stop was handled as a failure"
            )

        default:
            return CaptureFailure(
                code: .internalFailure,
                summary: "screen capture stopped unexpectedly"
            )
        }
    }
}
