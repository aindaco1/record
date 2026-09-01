import AppKit
import RecordCore

@MainActor
final class ShortcutRecorderButton: NSButton {
    let kind: ScreenshotCaptureKind
    var onRecord: ((ScreenshotShortcut?) -> Void)?
    var onInvalid: ((String) -> Void)?

    private var restingTitle = "Off"
    private var isRecordingShortcut = false

    init(kind: ScreenshotCaptureKind) {
        self.kind = kind
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
        restingTitle = shortcut?.displayString ?? "Off"
        if !isRecordingShortcut { title = restingTitle }
    }

    @objc private func beginRecording() {
        isRecordingShortcut = true
        title = "Type shortcut · Delete = Off"
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
            onInvalid?("A screenshot shortcut must include at least one modifier key.")
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
            onInvalid?("That key combination can’t be used as a screenshot shortcut.")
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

/// Screenshot-only preferences. Recording, transcription, and plug-in
/// controls intentionally remain in their existing menu surfaces.
@MainActor
final class ScreenshotSettingsWindowController: NSWindowController {
    private let preferences: ScreenshotPreferences
    private let destinationLabel = NSTextField(labelWithString: "")
    private let formatPopup = NSPopUpButton()
    private let qualitySlider = NSSlider(
        value: 0.95,
        minValue: 0.5,
        maxValue: 1,
        target: nil,
        action: nil
    )
    private let qualityLabel = NSTextField(labelWithString: "95%")
    private let soundCheckbox = NSButton(
        checkboxWithTitle: "Play shutter sound", target: nil, action: nil)
    private let messageLabel = NSTextField(wrappingLabelWithString: "")
    private var shortcutButtons: [ScreenshotCaptureKind: ShortcutRecorderButton] = [:]

    var onChooseExportFolder: (() -> Void)?
    var onPreferencesChanged: (() -> Void)?

    init(preferences: ScreenshotPreferences) {
        self.preferences = preferences
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 470),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Screenshot Settings"
        window.contentMinSize = NSSize(width: 640, height: 470)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildUI()
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func show(exportDirectory: URL) {
        updateExportDirectory(exportDirectory)
        refresh()
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func updateExportDirectory(_ url: URL) {
        destinationLabel.stringValue = url.path
        destinationLabel.toolTip = url.path
    }

    func showShortcutRegistrationFailures(
        _ failures: [GlobalScreenshotShortcutFailure]
    ) {
        guard !failures.isEmpty else {
            messageLabel.stringValue = ""
            return
        }
        let names = failures.map(\.kind.displayName).joined(separator: ", ")
        messageLabel.stringValue =
            "Couldn’t register: \(names). Another app or macOS is using the shortcut."
    }

    private func buildUI() {
        guard let contentView = window?.contentView else { return }
        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 14
        root.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(root)

        let heading = NSTextField(labelWithString: "Screenshots")
        heading.font = .systemFont(ofSize: 22, weight: .semibold)
        root.addArrangedSubview(heading)
        root.addArrangedSubview(
            NSTextField(
                wrappingLabelWithString:
                    "Captures save immediately to the shared export folder and copy a lossless PNG to the clipboard."
            )
        )

        let chooseButton = NSButton(
            title: "Select Export Folder…",
            target: self,
            action: #selector(chooseExportFolder)
        )
        destinationLabel.lineBreakMode = .byTruncatingMiddle
        destinationLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        root.addArrangedSubview(row(label: "Save to", views: [destinationLabel, chooseButton]))

        formatPopup.addItems(withTitles: ScreenshotImageFormat.allCases.map(\.displayName))
        formatPopup.target = self
        formatPopup.action = #selector(formatChanged)
        root.addArrangedSubview(row(label: "Format", views: [formatPopup]))

        qualitySlider.numberOfTickMarks = 11
        qualitySlider.allowsTickMarkValuesOnly = false
        qualitySlider.target = self
        qualitySlider.action = #selector(qualityChanged)
        qualitySlider.translatesAutoresizingMaskIntoConstraints = false
        qualitySlider.widthAnchor.constraint(equalToConstant: 220).isActive = true
        root.addArrangedSubview(row(label: "JPEG quality", views: [qualitySlider, qualityLabel]))

        soundCheckbox.target = self
        soundCheckbox.action = #selector(soundChanged)
        root.addArrangedSubview(row(label: "Feedback", views: [soundCheckbox]))

        let shortcutHeading = NSTextField(labelWithString: "Global Shortcuts")
        shortcutHeading.font = .systemFont(ofSize: 15, weight: .semibold)
        root.addArrangedSubview(shortcutHeading)
        for kind in ScreenshotCaptureKind.allCases {
            let button = ShortcutRecorderButton(kind: kind)
            button.onRecord = { [weak self] shortcut in
                self?.storeShortcut(shortcut, for: kind)
            }
            button.onInvalid = { [weak self] message in
                self?.messageLabel.stringValue = message
            }
            shortcutButtons[kind] = button
            root.addArrangedSubview(row(label: kind.displayName, views: [button]))
        }

        let reset = NSButton(
            title: "Restore Defaults",
            target: self,
            action: #selector(restoreDefaults)
        )
        let systemShortcuts = NSButton(
            title: "Open macOS Keyboard Shortcuts…",
            target: self,
            action: #selector(openSystemShortcuts)
        )
        root.addArrangedSubview(row(label: "", views: [reset, systemShortcuts]))

        messageLabel.textColor = .systemOrange
        messageLabel.maximumNumberOfLines = 2
        root.addArrangedSubview(messageLabel)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            root.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 22),
            root.bottomAnchor.constraint(
                lessThanOrEqualTo: contentView.bottomAnchor, constant: -20),
        ])
    }

    private func row(label: String, views: [NSView]) -> NSStackView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false
        let labelView = NSTextField(labelWithString: label)
        labelView.alignment = .right
        labelView.translatesAutoresizingMaskIntoConstraints = false
        labelView.widthAnchor.constraint(equalToConstant: 170).isActive = true
        labelView.setContentCompressionResistancePriority(.required, for: .horizontal)
        row.addArrangedSubview(labelView)
        for view in views { row.addArrangedSubview(view) }
        return row
    }

    private func refresh() {
        formatPopup.selectItem(at: preferences.format == .png ? 0 : 1)
        qualitySlider.doubleValue = preferences.jpegQuality
        qualityLabel.stringValue = "\(Int((preferences.jpegQuality * 100).rounded()))%"
        qualitySlider.isEnabled = preferences.format == .jpeg
        qualityLabel.textColor = preferences.format == .jpeg ? .labelColor : .secondaryLabelColor
        soundCheckbox.state = preferences.playShutterSound ? .on : .off
        let shortcuts = preferences.shortcuts
        for kind in ScreenshotCaptureKind.allCases {
            shortcutButtons[kind]?.update(shortcut: shortcuts[kind])
        }
    }

    private func storeShortcut(
        _ shortcut: ScreenshotShortcut?,
        for kind: ScreenshotCaptureKind
    ) {
        do {
            try preferences.setShortcut(shortcut, for: kind)
            messageLabel.stringValue = ""
            refresh()
            onPreferencesChanged?()
        } catch ScreenshotCaptureContractError.duplicateShortcut {
            messageLabel.stringValue =
                "That shortcut is already assigned to another screenshot command."
            NSSound.beep()
            refresh()
        } catch {
            messageLabel.stringValue = "That shortcut can’t be saved."
            NSSound.beep()
            refresh()
        }
    }

    @objc private func chooseExportFolder() { onChooseExportFolder?() }

    @objc private func formatChanged() {
        preferences.format = formatPopup.indexOfSelectedItem == 0 ? .png : .jpeg
        refresh()
        onPreferencesChanged?()
    }

    @objc private func qualityChanged() {
        preferences.jpegQuality = qualitySlider.doubleValue
        refresh()
        onPreferencesChanged?()
    }

    @objc private func soundChanged() {
        preferences.playShutterSound = soundCheckbox.state == .on
        onPreferencesChanged?()
    }

    @objc private func restoreDefaults() {
        preferences.restoreDefaultShortcuts()
        refresh()
        onPreferencesChanged?()
    }

    @objc private func openSystemShortcuts() {
        guard
            let url = URL(
                string:
                    "x-apple.systempreferences:com.apple.Keyboard-Settings.extension?Shortcuts"
            )
        else { return }
        NSWorkspace.shared.open(url)
    }
}
