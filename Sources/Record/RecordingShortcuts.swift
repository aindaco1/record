import Foundation
import RecordCore

enum RecordingShortcutAction: UInt32, CaseIterable, Sendable {
    case screen = 4, audio, pauseResume, dictation
    var title: String {
        switch self {
        case .screen: L10n.text("Screen start / stop")
        case .audio: L10n.text("Audio start / stop")
        case .dictation: L10n.text("Dictation start / stop")
        case .pauseResume: L10n.text("Screen pause / resume")
        }
    }
}

/// New shortcuts begin Off; existing screenshot assignments are untouched.
struct RecordingShortcuts {
    let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    subscript(action: RecordingShortcutAction) -> ScreenshotShortcut? {
        guard let data = defaults.data(forKey: key(action)),
            let value = try? JSONDecoder().decode(ScreenshotShortcut.self, from: data)
        else { return nil }
        return try? ScreenshotShortcut(
            keyCode: value.keyCode, modifiers: value.modifiers, keyLabel: value.keyLabel)
    }
    func set(
        _ shortcut: ScreenshotShortcut?, for action: RecordingShortcutAction,
        screenshots: ScreenshotShortcutSet
    ) throws {
        let others =
            RecordingShortcutAction.allCases.filter { $0 != action }.compactMap { self[$0] }
            + ScreenshotCaptureKind.allCases.compactMap { screenshots[$0] }
        try Self.check(shortcut, against: others)
        defaults.set(try shortcut.map { try JSONEncoder().encode($0) }, forKey: key(action))
    }
    static func check(_ shortcut: ScreenshotShortcut?, against others: [ScreenshotShortcut]) throws
    {
        guard let shortcut else { return }
        guard !others.contains(where: { $0.matchesKeys(of: shortcut) }) else {
            throw ScreenshotCaptureContractError.duplicateShortcut
        }
    }
    private func key(_ action: RecordingShortcutAction) -> String {
        "recording.shortcut.\(action.rawValue)"
    }
}
