import CoreMedia
import RecordCapture

public struct MediaTimelinePosition: Equatable, Sendable {
    public let presentationTime: CMTime
    public let timeSinceAnchor: CMTime
}

public enum MediaTimelineError: Error, Equatable, Sendable {
    case clockEpochMismatch(
        kind: ScreenCaptureSampleKind,
        expected: CMTimeEpoch,
        actual: CMTimeEpoch
    )
    case beforeAnchor(kind: ScreenCaptureSampleKind, presentationTime: CMTime)
    case nonMonotonic(
        kind: ScreenCaptureSampleKind,
        previous: CMTime,
        current: CMTime
    )
}

/// Maps samples that already use the host-time clock onto one immutable
/// session anchor. It preserves gaps and rejects per-track clock regressions.
public struct CommonMediaTimeline: Sendable {
    public let anchor: ScreenCaptureTimestamp

    private var latest: [ScreenCaptureSampleKind: CMTime] = [:]

    public init(anchor: CMTime) throws {
        self.anchor = try ScreenCaptureTimestamp(validating: anchor)
    }

    public mutating func position(
        for presentationTime: CMTime,
        kind: ScreenCaptureSampleKind
    ) throws -> MediaTimelinePosition {
        let validated = try ScreenCaptureTimestamp(validating: presentationTime)
        guard validated.time.epoch == anchor.time.epoch else {
            throw MediaTimelineError.clockEpochMismatch(
                kind: kind,
                expected: anchor.time.epoch,
                actual: validated.time.epoch
            )
        }
        guard CMTimeCompare(validated.time, anchor.time) >= 0 else {
            throw MediaTimelineError.beforeAnchor(
                kind: kind,
                presentationTime: validated.time
            )
        }
        if let previous = latest[kind], CMTimeCompare(validated.time, previous) < 0 {
            throw MediaTimelineError.nonMonotonic(
                kind: kind,
                previous: previous,
                current: validated.time
            )
        }
        latest[kind] = validated.time
        return MediaTimelinePosition(
            presentationTime: validated.time,
            timeSinceAnchor: CMTimeSubtract(validated.time, anchor.time)
        )
    }
}
