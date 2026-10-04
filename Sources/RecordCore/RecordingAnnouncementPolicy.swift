import Foundation

/// Stable capture transitions only. Clock ticks, meters, and health text must
/// never cause repeated screen-reader announcements.
public struct RecordingAnnouncementPolicy: Sendable {
    public enum State: Sendable { case idle, recording, paused }
    private var state: State = .idle
    public init() {}

    public mutating func transition(to next: State) -> String? {
        guard state != next else { return nil }
        defer { state = next }
        switch next {
        case .idle: return L10n.text("Recording stopped")
        case .paused: return L10n.text("Recording paused")
        case .recording:
            return L10n.text(state == .paused ? "Recording resumed" : "Recording started")
        }
    }
}
