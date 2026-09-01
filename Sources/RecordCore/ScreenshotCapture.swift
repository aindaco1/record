import Foundation

public enum ScreenshotCaptureKind: String, CaseIterable, Codable, Sendable {
    case display
    case windowOrApplication
    case area

    public var displayName: String {
        switch self {
        case .display: "Full Display"
        case .windowOrApplication: "Window or Application"
        case .area: "Area"
        }
    }

    /// Apple's private window/application picker grants access only to the
    /// explicit selection. Full-display and custom-area capture instead build
    /// a display filter directly and therefore require Screen Recording access.
    public var requiresDirectScreenCaptureAccess: Bool {
        switch self {
        case .display, .area: true
        case .windowOrApplication: false
        }
    }
}

public enum ScreenshotImageFormat: String, CaseIterable, Codable, Sendable {
    case png
    case jpeg

    public var fileExtension: String {
        switch self {
        case .png: "png"
        case .jpeg: "jpg"
        }
    }

    public var displayName: String {
        switch self {
        case .png: "PNG (Lossless)"
        case .jpeg: "JPEG"
        }
    }
}

/// Still images deliberately do not inherit Record's 4K/even-dimension video
/// writer limit. A screenshot retains the source's complete native pixel size.
public struct ScreenshotPixelSize: Equatable, Sendable {
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) throws {
        guard width > 0, height > 0 else {
            throw ScreenshotCaptureContractError.invalidPixelSize
        }
        self.width = width
        self.height = height
    }
}

public enum ScreenshotCaptureContractError: Error, Equatable {
    case invalidPixelSize
    case invalidShortcut
    case duplicateShortcut
}

public struct ScreenshotShortcutModifiers: OptionSet, Codable, Equatable, Hashable, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let command = Self(rawValue: 1 << 0)
    public static let shift = Self(rawValue: 1 << 1)
    public static let option = Self(rawValue: 1 << 2)
    public static let control = Self(rawValue: 1 << 3)
}

public struct ScreenshotShortcut: Codable, Equatable, Hashable, Sendable {
    public let keyCode: UInt32
    public let modifiers: ScreenshotShortcutModifiers
    /// A bounded display label captured with the physical key code. It is UI
    /// presentation only; registration never parses or executes this string.
    public let keyLabel: String

    public init(
        keyCode: UInt32,
        modifiers: ScreenshotShortcutModifiers,
        keyLabel: String
    ) throws {
        let label = keyLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard keyCode <= UInt16.max, !modifiers.isEmpty, !label.isEmpty, label.count <= 8 else {
            throw ScreenshotCaptureContractError.invalidShortcut
        }
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyLabel = label
    }

    public var displayString: String {
        var value = ""
        if modifiers.contains(.control) { value += "⌃" }
        if modifiers.contains(.option) { value += "⌥" }
        if modifiers.contains(.shift) { value += "⇧" }
        if modifiers.contains(.command) { value += "⌘" }
        return value + keyLabel.uppercased()
    }
}

public struct ScreenshotShortcutSet: Equatable, Sendable {
    public var display: ScreenshotShortcut?
    public var windowOrApplication: ScreenshotShortcut?
    public var area: ScreenshotShortcut?

    public init(
        display: ScreenshotShortcut?,
        windowOrApplication: ScreenshotShortcut?,
        area: ScreenshotShortcut?
    ) throws {
        self.display = display
        self.windowOrApplication = windowOrApplication
        self.area = area
        try validate()
    }

    public static var defaults: Self {
        // ANSI number-row virtual key codes: 1 = 18, 2 = 19, 4 = 21.
        try! Self(
            display: ScreenshotShortcut(
                keyCode: 18,
                modifiers: [.command, .shift],
                keyLabel: "1"
            ),
            windowOrApplication: ScreenshotShortcut(
                keyCode: 19,
                modifiers: [.command, .shift],
                keyLabel: "2"
            ),
            area: ScreenshotShortcut(
                keyCode: 21,
                modifiers: [.command, .shift],
                keyLabel: "4"
            )
        )
    }

    public subscript(kind: ScreenshotCaptureKind) -> ScreenshotShortcut? {
        get {
            switch kind {
            case .display: display
            case .windowOrApplication: windowOrApplication
            case .area: area
            }
        }
        set {
            switch kind {
            case .display: display = newValue
            case .windowOrApplication: windowOrApplication = newValue
            case .area: area = newValue
            }
        }
    }

    public func validate() throws {
        let enabled = ScreenshotCaptureKind.allCases.compactMap { self[$0] }
        guard Set(enabled).count == enabled.count else {
            throw ScreenshotCaptureContractError.duplicateShortcut
        }
    }
}

public enum ScreenshotFileNamePolicy {
    public static func baseName(
        at date: Date,
        calendar: Calendar = .current,
        timeZone: TimeZone = .current
    ) -> String {
        var calendar = calendar
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )
        return String(
            format: "Screenshot %04d-%02d-%02d at %02d.%02d.%02d",
            parts.year ?? 0,
            parts.month ?? 0,
            parts.day ?? 0,
            parts.hour ?? 0,
            parts.minute ?? 0,
            parts.second ?? 0
        )
    }

    public static func nextAvailableURL(
        in directory: URL,
        at date: Date,
        format: ScreenshotImageFormat,
        calendar: Calendar = .current,
        timeZone: TimeZone = .current,
        fileExists: (URL) -> Bool
    ) -> URL {
        let base = baseName(at: date, calendar: calendar, timeZone: timeZone)
        var suffix = 1
        while true {
            let name = suffix == 1 ? base : "\(base)-\(suffix)"
            let candidate = directory.appendingPathComponent(
                "\(name).\(format.fileExtension)",
                isDirectory: false
            )
            if !fileExists(candidate) { return candidate }
            suffix += 1
        }
    }
}

public enum ScreenshotFeedbackPolicy {
    public static func shouldPlayShutter(
        preferenceEnabled: Bool,
        recordingIsActive: Bool
    ) -> Bool {
        preferenceEnabled && !recordingIsActive
    }
}
