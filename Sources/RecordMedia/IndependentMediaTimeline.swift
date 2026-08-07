import CoreMedia
import RecordCapture

public struct MediaTimelinePosition: Equatable, Sendable {
    public let presentationTime: CMTime
    public let trackAnchor: CMTime
    public let timeSinceTrackAnchor: CMTime
}

public enum MediaTimelineError: Error, Equatable, Sendable {
    case clockEpochMismatch(
        kind: ScreenCaptureSampleKind,
        expected: CMTimeEpoch,
        actual: CMTimeEpoch
    )
    case nonMonotonic(
        kind: ScreenCaptureSampleKind,
        previous: CMTime,
        current: CMTime
    )
}

/// Validates samples on one capture clock while allowing each independently
/// written track to begin at its own first timestamp. ScreenCaptureKit invokes
/// the output queues independently, so first-arrival order is not necessarily
/// timestamp order.
public struct IndependentMediaTimeline: Sendable {
    private var epoch: CMTimeEpoch?
    private var first: [ScreenCaptureSampleKind: ScreenCaptureTimestamp] = [:]
    private var latest: [ScreenCaptureSampleKind: ScreenCaptureTimestamp] = [:]

    public init() {}

    public mutating func observe(
        _ presentationTime: CMTime,
        kind: ScreenCaptureSampleKind
    ) throws -> MediaTimelinePosition {
        let timestamp = try ScreenCaptureTimestamp(validating: presentationTime)
        if let epoch {
            guard timestamp.time.epoch == epoch else {
                throw MediaTimelineError.clockEpochMismatch(
                    kind: kind,
                    expected: epoch,
                    actual: timestamp.time.epoch
                )
            }
        } else {
            epoch = timestamp.time.epoch
        }

        if let previous = latest[kind], CMTimeCompare(timestamp.time, previous.time) < 0 {
            throw MediaTimelineError.nonMonotonic(
                kind: kind,
                previous: previous.time,
                current: timestamp.time
            )
        }

        let trackAnchor: ScreenCaptureTimestamp
        if let existing = first[kind] {
            trackAnchor = existing
        } else {
            first[kind] = timestamp
            trackAnchor = timestamp
        }
        latest[kind] = timestamp

        return MediaTimelinePosition(
            presentationTime: timestamp.time,
            trackAnchor: trackAnchor.time,
            timeSinceTrackAnchor: CMTimeSubtract(timestamp.time, trackAnchor.time)
        )
    }

    public var startOffsetMilliseconds: [ScreenCaptureSampleKind: Int] {
        guard
            let earliest = first.values.min(by: {
                CMTimeCompare($0.time, $1.time) < 0
            })
        else {
            return [:]
        }

        return Dictionary(
            uniqueKeysWithValues: first.compactMap { kind, timestamp in
                let seconds = CMTimeGetSeconds(CMTimeSubtract(timestamp.time, earliest.time))
                guard seconds.isFinite else { return nil }
                return (kind, max(0, Int((seconds * 1_000).rounded())))
            }
        )
    }
}
