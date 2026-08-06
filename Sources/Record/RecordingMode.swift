enum RecordingMode: String, Sendable {
    case screen
    case audioOnly

    var displayName: String {
        switch self {
        case .screen: "screen"
        case .audioOnly: "audio"
        }
    }
}
