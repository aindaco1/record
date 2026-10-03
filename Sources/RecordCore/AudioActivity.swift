import Foundation

/// One bounded, content-free sample for UI polling. Capture never waits for UI.
public final class AudioActivity: @unchecked Sendable {
    private let lock = NSLock()
    private var peak: Double = 0
    private var updatedAt = Date.distantPast
    public init() {}
    public var hasReceivedSamples: Bool { lock.withLock { updatedAt != .distantPast } }
    public func record(peak: Double, at date: Date = Date()) {
        guard lock.try() else { return }
        self.peak = peak.isFinite ? min(1, max(0, peak)) : 0
        updatedAt = date
        lock.unlock()
    }
    public func level(at date: Date = Date()) -> Double {
        lock.withLock {
            guard date.timeIntervalSince(updatedAt) < 1 else { return 0 }
            return peak > 0 ? max(0, min(1, (20 * log10(peak) + 60) / 60)) : 0
        }
    }
    public func reset() {
        lock.withLock {
            peak = 0; updatedAt = .distantPast
        }
    }
}
