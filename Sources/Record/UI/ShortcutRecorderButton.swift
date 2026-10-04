import AppKit
import RecordCore

@MainActor
final class ShortcutRecorderButton: NSButton {
    var onRecord: ((ScreenshotShortcut?) -> Void)?
    var onInvalid: ((String) -> Void)?

    private var restingTitle = L10n.text("Off")
    private(set) var isRecordingShortcut = false

    init(kind: ScreenshotCaptureKind? = nil) {
        super.init(frame: .zero)
        bezelStyle = .rounded
        target = self
        action = #selector(beginRecording)
        setButtonType(.momentaryPushIn)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(greaterThanOrEqualToConstant: 170).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { true }

    func update(shortcut: ScreenshotShortcut?) {
        restingTitle = shortcut?.displayString ?? L10n.text("Off")
        if !isRecordingShortcut { title = restingTitle }
    }

    @objc private func beginRecording() {
        isRecordingShortcut = true
        title = L10n.text("Type shortcut · Delete = Off")
        window?.makeFirstResponder(self)
    }

    override func resignFirstResponder() -> Bool {
        finishRecording()
        return super.resignFirstResponder()
    }

    override func keyDown(with event: NSEvent) {
        guard isRecordingShortcut else {
            super.keyDown(with: event)
            return
        }
        if event.keyCode == 53 {
            finishRecording()
            return
        }
        if event.keyCode == 51 || event.keyCode == 117 {
            onRecord?(nil)
            finishRecording()
            return
        }

        let modifiers = Self.shortcutModifiers(from: event.modifierFlags)
        guard !modifiers.isEmpty else {
            onInvalid?(L10n.text("A shortcut must include at least one modifier key."))
            NSSound.beep()
            return
        }
        let label = Self.keyLabel(for: event)
        do {
            let shortcut = try ScreenshotShortcut(
                keyCode: UInt32(event.keyCode),
                modifiers: modifiers,
                keyLabel: label
            )
            onRecord?(shortcut)
            finishRecording()
        } catch {
            onInvalid?(L10n.text("That key combination can’t be used as a shortcut."))
            NSSound.beep()
        }
    }

    static func shortcutModifiers(
        from flags: NSEvent.ModifierFlags
    ) -> ScreenshotShortcutModifiers {
        var result: ScreenshotShortcutModifiers = []
        if flags.contains(.command) { result.insert(.command) }
        if flags.contains(.shift) { result.insert(.shift) }
        if flags.contains(.option) { result.insert(.option) }
        if flags.contains(.control) { result.insert(.control) }
        return result
    }

    private static func keyLabel(for event: NSEvent) -> String {
        let characters =
            event.charactersIgnoringModifiers?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !characters.isEmpty, characters.count <= 8 {
            return characters.uppercased()
        }
        return "Key(event.keyCode)"
    }

    private func finishRecording() {
        isRecordingShortcut = false
        title = restingTitle
    }
}
