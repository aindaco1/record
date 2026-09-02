import Foundation
import RecordCore

@MainActor
final class ScreenshotPreferences {
    static let formatKey = "screenshots.imageFormat"
    static let jpegQualityKey = "screenshots.jpegQuality"
    static let shutterSoundKey = "screenshots.playShutterSound"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var format: ScreenshotImageFormat {
        get {
            defaults.string(forKey: Self.formatKey)
                .flatMap(ScreenshotImageFormat.init(rawValue:)) ?? .png
        }
        set {
            defaults.set(newValue.rawValue, forKey: Self.formatKey)
        }
    }

    var jpegQuality: Double {
        get {
            guard defaults.object(forKey: Self.jpegQualityKey) != nil else { return 0.95 }
            return Self.validatedQuality(defaults.double(forKey: Self.jpegQualityKey))
        }
        set {
            defaults.set(Self.validatedQuality(newValue), forKey: Self.jpegQualityKey)
        }
    }

    var playShutterSound: Bool {
        get {
            defaults.object(forKey: Self.shutterSoundKey) as? Bool ?? true
        }
        set {
            defaults.set(newValue, forKey: Self.shutterSoundKey)
        }
    }

    var shortcuts: ScreenshotShortcutSet {
        get {
            let defaultsSet = ScreenshotShortcutSet.defaults
            return
                (try? ScreenshotShortcutSet(
                    display: shortcut(for: .display, fallback: defaultsSet.display),
                    windowOrApplication: shortcut(
                        for: .windowOrApplication,
                        fallback: defaultsSet.windowOrApplication
                    ),
                    area: shortcut(for: .area, fallback: defaultsSet.area)
                )) ?? defaultsSet
        }
        set {
            guard (try? newValue.validate()) != nil else { return }
            for kind in ScreenshotCaptureKind.allCases {
                store(newValue[kind], for: kind)
            }
        }
    }

    func setShortcut(
        _ shortcut: ScreenshotShortcut?,
        for kind: ScreenshotCaptureKind
    ) throws {
        var next = shortcuts
        next[kind] = shortcut
        try next.validate()
        shortcuts = next
    }

    func restoreDefaultShortcuts() {
        shortcuts = .defaults
    }

    private func shortcut(
        for kind: ScreenshotCaptureKind,
        fallback: ScreenshotShortcut?
    ) -> ScreenshotShortcut? {
        let prefix = shortcutPrefix(for: kind)
        guard defaults.object(forKey: "\(prefix).enabled") != nil else {
            return fallback
        }
        guard defaults.bool(forKey: "\(prefix).enabled") else { return nil }
        let keyCode = UInt32(clamping: defaults.integer(forKey: "\(prefix).keyCode"))
        let modifiers = ScreenshotShortcutModifiers(
            rawValue: UInt32(clamping: defaults.integer(forKey: "\(prefix).modifiers"))
        )
        let label = defaults.string(forKey: "\(prefix).keyLabel") ?? ""
        return
            (try? ScreenshotShortcut(
                keyCode: keyCode,
                modifiers: modifiers,
                keyLabel: label
            )) ?? fallback
    }

    private func store(
        _ shortcut: ScreenshotShortcut?,
        for kind: ScreenshotCaptureKind
    ) {
        let prefix = shortcutPrefix(for: kind)
        defaults.set(shortcut != nil, forKey: "\(prefix).enabled")
        guard let shortcut else {
            defaults.removeObject(forKey: "\(prefix).keyCode")
            defaults.removeObject(forKey: "\(prefix).modifiers")
            defaults.removeObject(forKey: "\(prefix).keyLabel")
            return
        }
        defaults.set(Int(shortcut.keyCode), forKey: "\(prefix).keyCode")
        defaults.set(Int(shortcut.modifiers.rawValue), forKey: "\(prefix).modifiers")
        defaults.set(shortcut.keyLabel, forKey: "\(prefix).keyLabel")
    }

    private func shortcutPrefix(for kind: ScreenshotCaptureKind) -> String {
        "screenshots.shortcut.\(kind.rawValue)"
    }

    private static func validatedQuality(_ value: Double) -> Double {
        guard value.isFinite else { return 0.95 }
        return min(1, max(0.5, value))
    }
}
