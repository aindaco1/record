import Foundation

public enum MicrophoneSelectionPolicy {
    /// VoiceProcessingIO owns a duplex default route. Pinning its CurrentDevice
    /// to an input-only device can invalidate its output. Explicit inputs use
    /// raw capture rather than changing the user's output or creating devices.
    public static func usesVoiceProcessing(requested: Bool, deviceID: String?) -> Bool {
        requested && deviceID == nil
    }
    /// System Default may follow the OS route. An explicit choice never does.
    public static func isAvailable(_ audio: CaptureAudioConfiguration, deviceIDs: Set<String>)
        -> Bool
    {
        guard audio.includeMicrophone, let selected = audio.microphoneDeviceID else { return true }
        return deviceIDs.contains(selected)
    }
}

/// Never put a modal input chooser ahead of asynchronous media finalization.
public struct SelectedMicrophoneRecovery: Sendable {
    public enum Event: Sendable { case deviceLost, recordingPreserved }
    public enum Action: Equatable, Sendable { case stopRecording, offerInput }
    private var stopping = false
    public init() {}
    public mutating func handle(_ event: Event) -> Action? {
        switch event {
        case .deviceLost:
            guard !stopping else { return nil }
            stopping = true
            return .stopRecording
        case .recordingPreserved:
            guard stopping else { return nil }
            stopping = false
            return .offerInput
        }
    }
}
