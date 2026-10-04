import AppIntents
import RecordCore

/// Installed by the existing AppKit launch path. Intents request that the app
/// open, then hand off to the same handler as the private CLI mailbox.
@MainActor
enum RecordingIntentBridge {
    static var handler: ((RecordingControl.Request) -> RecordingControl.Response)?

    static func perform(_ action: RecordingControl.Action, mode: RecordingControl.Mode? = nil)
        async throws -> String
    {
        guard let handler else { throw RecordingControlMailbox.MailboxError.unavailable }
        let response = handler(.init(instance: UUID(), action: action, mode: mode))
        if let failure = response.failure {
            throw IntentError.command(ControlRecording.message(for: failure))
        }
        switch response.snapshot.phase {
        case .idle: return L10n.text("Idle")
        case .preparing: return L10n.text("Preparing recording")
        case .recording: return L10n.text("Recording")
        case .pausing: return L10n.text("Pausing recording")
        case .paused: return L10n.text("Paused")
        case .resuming: return L10n.text("Resuming recording")
        case .stopping: return L10n.text("Stopping recording")
        case .saving: return L10n.text("Saving recording")
        }
    }

    private enum IntentError: Error, LocalizedError {
        case command(String)
        var errorDescription: String? {
            switch self {
            case .command(let message): L10n.text(message)
            }
        }
    }
}

enum RecordingIntentMode: String, AppEnum {
    case screen, audio, dictation
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Recording mode"
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .screen: "Screen", .audio: "Audio only", .dictation: "Quick Dictation",
    ]
    var controlMode: RecordingControl.Mode {
        switch self {
        case .screen: .screen;
        case .audio: .audio;
        case .dictation: .dictation
        }
    }
}

struct StartRecordingIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Recording"
    static let description = IntentDescription(
        "Start a recording using your saved Record settings.")
    static let openAppWhenRun = true
    @Parameter(title: "Recording mode", default: .screen) var mode: RecordingIntentMode
    static var parameterSummary: some ParameterSummary { Summary("Start \(\.$mode) recording") }
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        .result(value: try await RecordingIntentBridge.perform(.start, mode: mode.controlMode))
    }
}

struct StopRecordingIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop Recording"
    static let description = IntentDescription(
        "Stop capture and preserve the recording. Use Status to check when saving finishes.")
    static let openAppWhenRun = true
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        .result(value: try await RecordingIntentBridge.perform(.stop))
    }
}

struct PauseRecordingIntent: AppIntent {
    static let title: LocalizedStringResource = "Pause Recording"
    static let description = IntentDescription("Pause an active screen recording.")
    static let openAppWhenRun = true
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        .result(value: try await RecordingIntentBridge.perform(.pause))
    }
}

struct ResumeRecordingIntent: AppIntent {
    static let title: LocalizedStringResource = "Resume Recording"
    static let description = IntentDescription("Resume a paused screen recording.")
    static let openAppWhenRun = true
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        .result(value: try await RecordingIntentBridge.perform(.resume))
    }
}

struct RecordingStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Recording Status"
    static let description = IntentDescription(
        "Get Record’s current capture state without sharing recording content.")
    static let openAppWhenRun = true
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        .result(value: try await RecordingIntentBridge.perform(.status))
    }
}

struct RecordAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartRecordingIntent(), phrases: ["Start recording with \(.applicationName)"],
            shortTitle: "Start Recording", systemImageName: "record.circle")
        AppShortcut(
            intent: StopRecordingIntent(), phrases: ["Stop recording with \(.applicationName)"],
            shortTitle: "Stop Recording", systemImageName: "stop.circle")
        AppShortcut(
            intent: PauseRecordingIntent(), phrases: ["Pause recording with \(.applicationName)"],
            shortTitle: "Pause Recording", systemImageName: "pause.circle")
        AppShortcut(
            intent: ResumeRecordingIntent(), phrases: ["Resume recording with \(.applicationName)"],
            shortTitle: "Resume Recording", systemImageName: "play.circle")
        AppShortcut(
            intent: RecordingStatusIntent(),
            phrases: ["Get recording status in \(.applicationName)"],
            shortTitle: "Recording Status", systemImageName: "info.circle")
    }
}
