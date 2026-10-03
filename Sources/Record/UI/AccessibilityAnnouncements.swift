import AppKit
import RecordCore

@MainActor
final class AccessibilityAnnouncements {
    private var recording = RecordingAnnouncementPolicy()
    private var lastTranscription: String?

    func update(_ presentation: RecordingMenuPresentation) {
        let state: RecordingAnnouncementPolicy.State
        if presentation == .idle {
            state = .idle
        } else if presentation.toggleEnabled && !presentation.audioOnlyEnabled {
            state = presentation.recordingIndicatorActive ? .recording : .paused
        } else {
            return
        }
        if let message = recording.transition(to: state) { Self.post(message) }
    }

    func update(_ status: TranscriptionCoordinator.Status) {
        let key: String
        let message: String
        switch status {
        case .progress: return
        case .transcribing:
            key = "working"; message = L10n.text("Transcription started")
        case .idle:
            key = "idle"; message = L10n.text("Transcription finished")
        case .failed:
            key = "failed"; message = L10n.text("Transcription couldn’t finish")
        case .deferred:
            key = "deferred"; message = L10n.text("Transcription deferred · recording preserved")
        }
        defer { lastTranscription = key }
        guard key != lastTranscription, key != "idle" || lastTranscription == "working" else {
            return
        }
        Self.post(message)
    }

    static func post(_ message: String) {
        NSAccessibility.post(
            element: NSApp as Any, notification: .announcementRequested,
            userInfo: [
                .announcement: message, .priority: NSAccessibilityPriorityLevel.medium.rawValue,
            ])
    }
}
