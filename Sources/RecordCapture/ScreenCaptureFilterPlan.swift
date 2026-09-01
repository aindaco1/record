import Foundation
import RecordCore

/// A value-only filter plan that keeps ScreenCaptureKit policy deterministic
/// and testable without constructing framework-owned window objects.
public struct ScreenCaptureFilterPlan: Equatable, Sendable {
    public enum OwnApplicationPolicy: Equatable, Sendable {
        case exclude
        case include
    }

    public struct Window: Equatable, Sendable {
        public let id: UInt32
        public let ownerBundleIdentifier: String?
        public let layer: Int

        public init(id: UInt32, ownerBundleIdentifier: String?, layer: Int) {
            self.id = id
            self.ownerBundleIdentifier = ownerBundleIdentifier
            self.layer = layer
        }
    }

    public static let finderBundleIdentifier = "com.apple.finder"
    public static let notificationCenterBundleIdentifiers: Set<String> = [
        "com.apple.notificationcenterui"
    ]

    public let includeMenuBar: Bool
    public let excludedApplicationBundleIdentifiers: Set<String>
    public let exceptedWindowIDs: Set<UInt32>

    public init(
        privacy: CapturePrivacyConfiguration,
        ownBundleIdentifier: String?,
        ownApplicationPolicy: OwnApplicationPolicy = .exclude,
        availableApplicationBundleIdentifiers: Set<String>,
        windows: [Window]
    ) {
        includeMenuBar = !privacy.hideMenuBar

        var excluded = Self.privacyApplicationExclusions(
            privacy: privacy,
            ownBundleIdentifier: ownBundleIdentifier,
            ownApplicationPolicy: ownApplicationPolicy
        )

        var exceptedWindows = Set<UInt32>()
        if privacy.hideDesktopItems,
            availableApplicationBundleIdentifiers.contains(Self.finderBundleIdentifier)
        {
            excluded.insert(Self.finderBundleIdentifier)
            exceptedWindows.formUnion(
                windows.lazy
                    .filter {
                        $0.ownerBundleIdentifier == Self.finderBundleIdentifier
                            && !Self.isDesktopWindow($0)
                    }
                    .map(\.id)
            )
        }

        excludedApplicationBundleIdentifiers = excluded
        exceptedWindowIDs = exceptedWindows
    }

    public static func privacyApplicationExclusions(
        privacy: CapturePrivacyConfiguration,
        ownBundleIdentifier: String?,
        ownApplicationPolicy: OwnApplicationPolicy
    ) -> Set<String> {
        var excluded = Set<String>()
        if ownApplicationPolicy == .exclude, let ownBundleIdentifier {
            excluded.insert(ownBundleIdentifier)
        }
        if privacy.hideNotifications {
            excluded.formUnion(notificationCenterBundleIdentifiers)
        }
        return excluded
    }

    /// Finder's desktop surface lives below normal windows. Excluding that
    /// surface removes desktop items while ScreenCaptureKit keeps the wallpaper.
    public static func isDesktopWindow(_ window: Window) -> Bool {
        window.ownerBundleIdentifier == finderBundleIdentifier && window.layer < 0
    }
}
