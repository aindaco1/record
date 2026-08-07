import Foundation

/// Tracks captured time separately from wall time so paused intervals and
/// stream-restart latency do not inflate the menu counter.
struct RecordingElapsedClock: Equatable {
    private(set) var captured: TimeInterval = 0
    private(set) var activeSince: Date?

    mutating func start(at date: Date) {
        captured = 0
        activeSince = date
    }

    mutating func pause(at date: Date) {
        guard let activeSince else { return }
        captured += max(0, date.timeIntervalSince(activeSince))
        self.activeSince = nil
    }

    mutating func resume(at date: Date) {
        guard activeSince == nil else { return }
        activeSince = date
    }

    mutating func stop(at date: Date) -> TimeInterval {
        pause(at: date)
        return captured
    }

    func elapsed(at date: Date) -> TimeInterval {
        captured + (activeSince.map { max(0, date.timeIntervalSince($0)) } ?? 0)
    }

    var isPaused: Bool { activeSince == nil }
}
