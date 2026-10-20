import Foundation
import RecordCore

enum RecordingAudioSource: String, CaseIterable {
    case both, microphone, system
    var title: String {
        switch self {
        case .both: L10n.text("Microphone + System Audio");
        case .microphone: L10n.text("Microphone Only");
        case .system: L10n.text("System Audio Only")
        }
    }
}

struct RecordingAudioPreferences {
    let defaults: UserDefaults
    private let appConfiguration: AppConfiguration
    init(defaults: UserDefaults = .standard, configuration: AppConfiguration = Config.current) {
        self.defaults = defaults
        self.appConfiguration = configuration
    }
    var voiceProcessing: Bool {
        get {
            defaults.object(forKey: "recording.voiceProcessing") as? Bool
                ?? appConfiguration.micVoiceProcessing
        }
        nonmutating set { defaults.set(newValue, forKey: "recording.voiceProcessing") }
    }
    var disableVoiceProcessingForZoom: Bool {
        get {
            defaults.object(forKey: "recording.disableVoiceProcessingForZoom") as? Bool
                ?? appConfiguration.micDisableVoiceProcessingForZoom
        }
        nonmutating set {
            defaults.set(newValue, forKey: "recording.disableVoiceProcessingForZoom")
        }
    }
    var automaticGainControl: Bool {
        get {
            defaults.object(forKey: "recording.automaticGainControl") as? Bool
                ?? appConfiguration.micAutomaticGainControl
        }
        nonmutating set { defaults.set(newValue, forKey: "recording.automaticGainControl") }
    }
    var usesVoiceProcessing: Bool {
        MicrophoneSelectionPolicy.usesVoiceProcessing(
            requested: voiceProcessing, deviceID: microphoneUID)
    }
    var source: RecordingAudioSource {
        get {
            defaults.string(forKey: "recording.audioSource").flatMap(
                RecordingAudioSource.init(rawValue:)) ?? .both
        }
        nonmutating set { defaults.set(newValue.rawValue, forKey: "recording.audioSource") }
    }
    var microphoneUID: String? {
        get { defaults.string(forKey: "recording.microphoneUID") }
        nonmutating set { defaults.set(newValue, forKey: "recording.microphoneUID") }
    }
    var showsPanel: Bool {
        get { defaults.object(forKey: "recording.showsPanel") as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: "recording.showsPanel") }
    }
    var configuration: CaptureAudioConfiguration {
        .init(
            includeSystemAudio: source != .microphone, includeMicrophone: source != .system,
            microphoneDeviceID: microphoneUID)
    }
}
