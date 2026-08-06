import Foundation
import RecordCore

@MainActor
final class CapturePrivacyPreferences {
    static let notificationsKey = "plugins.capturePrivacy.hideNotifications"
    static let menuBarKey = "plugins.capturePrivacy.hideMenuBar"
    static let desktopItemsKey = "plugins.capturePrivacy.hideDesktopItems"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var configuration: CapturePrivacyConfiguration {
        CapturePrivacyConfiguration(
            hideNotifications: value(forKey: Self.notificationsKey),
            hideMenuBar: value(forKey: Self.menuBarKey),
            hideDesktopItems: value(forKey: Self.desktopItemsKey)
        )
    }

    func toggle(_ feature: CapturePrivacyFeature) {
        let key = key(for: feature)
        defaults.set(!value(forKey: key), forKey: key)
    }

    private func value(forKey key: String) -> Bool {
        defaults.object(forKey: key) as? Bool ?? true
    }

    private func key(for feature: CapturePrivacyFeature) -> String {
        switch feature {
        case .notifications: Self.notificationsKey
        case .menuBar: Self.menuBarKey
        case .desktopItems: Self.desktopItemsKey
        }
    }
}
