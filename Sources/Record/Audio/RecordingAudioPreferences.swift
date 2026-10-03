import Foundation
import RecordCore

enum RecordingAudioSource: String, CaseIterable {
    case both, microphone, system
    var title: String {
        switch self {
        case .both: "Microphone + System Audio";
        case .microphone: "Microphone Only";
        case .system: "System Audio Only"
        }
    }
}

struct RecordingAudioPreferences {
    let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
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
