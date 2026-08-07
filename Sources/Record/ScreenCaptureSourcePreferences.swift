import Foundation

enum ScreenCaptureSourcePreference: String, CaseIterable, Sendable {
    case mainDisplay
    case systemPicker
    case region

    var displayName: String {
        switch self {
        case .mainDisplay: "Main Display"
        case .systemPicker: "Display, Application, or Window…"
        case .region: "Custom Region…"
        }
    }
}

/// Persists only the kind of selection flow. The selected application's name,
/// window title, display identifier, and region never enter preferences.
final class ScreenCaptureSourcePreferences {
    private static let defaultKey = "screenCaptureSourcePreference"
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = defaultKey) {
        self.defaults = defaults
        self.key = key
    }

    var selected: ScreenCaptureSourcePreference {
        get {
            guard let rawValue = defaults.string(forKey: key),
                let value = ScreenCaptureSourcePreference(rawValue: rawValue)
            else {
                return .mainDisplay
            }
            return value
        }
        set {
            defaults.set(newValue.rawValue, forKey: key)
        }
    }
}
