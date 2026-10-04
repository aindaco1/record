import RecordCore

enum RecordingMode: String, Sendable {
    case screen
    case audioOnly
    case dictation

    var controlMode: RecordingControl.Mode {
        switch self {
        case .screen: .screen
        case .audioOnly: .audio
        case .dictation: .dictation
        }
    }

    var displayName: String {
        switch self {
        case .screen: "screen"
        case .audioOnly: "audio"
        case .dictation: "dictation"
        }
    }
}
