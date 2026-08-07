import Foundation
import RecordCore

@MainActor
final class RecordingNamePreferences {
    static let enabledKey = "plugins.recordingName.enabled"
    static let templateKey = "plugins.recordingName.template"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isEnabled: Bool {
        get { defaults.object(forKey: Self.enabledKey) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Self.enabledKey) }
    }

    var template: RecordingNameTemplate {
        guard let stored = defaults.string(forKey: Self.templateKey),
            let template = try? RecordingNameTemplate(validating: stored)
        else {
            return .defaultValue
        }
        return template
    }

    func setTemplate(_ value: String) throws {
        let template = try RecordingNameTemplate(validating: value)
        defaults.set(template.rawValue, forKey: Self.templateKey)
    }

    func renderName(at date: Date, clipboard: @autoclosure () -> String?) -> String {
        let selected = isEnabled ? template : RecordingNameTemplate.legacyValue
        return selected.render(
            at: date,
            clipboard: selected.requiresClipboard ? clipboard() : nil,
            wordSeed: UInt64(max(0, date.timeIntervalSince1970 * 1_000))
        )
    }
}
