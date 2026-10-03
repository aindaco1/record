import Foundation

public struct RecordingReadiness: Equatable, Sendable {
    public let hasSaveFolder: Bool
    public let needsMicrophone: Bool
    public let microphoneGranted: Bool
    public let needsScreen: Bool
    public let screenGranted: Bool
    public let needsSystemAudio: Bool
    public let inputTested: Bool
    public let modelInstalled: Bool

    public init(
        hasSaveFolder: Bool, audio: CaptureAudioConfiguration,
        screenRecording: Bool, microphoneGranted: Bool, screenGranted: Bool,
        inputTested: Bool, modelInstalled: Bool
    ) {
        self.hasSaveFolder = hasSaveFolder
        needsMicrophone = audio.includeMicrophone
        self.microphoneGranted = microphoneGranted
        needsScreen = screenRecording
        self.screenGranted = screenGranted
        needsSystemAudio = audio.includeSystemAudio && !screenRecording
        self.inputTested = inputTested
        self.modelInstalled = modelInstalled
    }

    public var checklist: [String] {
        [
            hasSaveFolder ? L10n.text("✓ Save folder chosen") : L10n.text("Choose a save folder"),
            !needsMicrophone
                ? L10n.text("Microphone: not used")
                : (microphoneGranted
                    ? L10n.text("✓ Microphone permission") : L10n.text("Allow microphone access")),
            !needsScreen
                ? (needsSystemAudio
                    ? L10n.text("System audio permission: checked when you start")
                    : L10n.text("Screen access: not needed"))
                : (screenGranted
                    ? L10n.text("✓ Screen recording permission")
                    : L10n.text("Allow screen recording access")),
            !needsMicrophone
                ? L10n.text("Input test: not needed")
                : (inputTested
                    ? L10n.text("✓ Input test completed") : L10n.text("Test your microphone")),
            modelInstalled
                ? L10n.text("✓ Local transcription model ready")
                : L10n.text("Optional: set up local transcription (recording works without it)"),
        ]
    }
}
