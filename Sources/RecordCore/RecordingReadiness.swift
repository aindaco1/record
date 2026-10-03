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
            hasSaveFolder ? "✓ Save folder chosen" : "Choose a save folder",
            !needsMicrophone
                ? "Microphone: not used"
                : (microphoneGranted ? "✓ Microphone permission" : "Allow microphone access"),
            !needsScreen
                ? (needsSystemAudio
                    ? "System audio permission: checked when you start"
                    : "Screen access: not needed")
                : (screenGranted
                    ? "✓ Screen recording permission" : "Allow screen recording access"),
            !needsMicrophone
                ? "Input test: not needed"
                : (inputTested ? "✓ Input test completed" : "Test your microphone"),
            modelInstalled
                ? "✓ Local transcription model ready"
                : "Optional: set up local transcription (recording works without it)",
        ]
    }
}
