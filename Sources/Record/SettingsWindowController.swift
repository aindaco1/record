import AppKit
import RecordCore

struct SettingsInteractionAvailability: Equatable {
    let destinationSelectionEnabled: Bool
    let capturePrivacyEnabled: Bool

    static let idle = SettingsInteractionAvailability(
        destinationSelectionEnabled: true,
        capturePrivacyEnabled: true
    )
}

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

/// One native settings surface for shared capture policy, screenshots, and
/// finished recordings. AppController remains the policy owner; this object
/// only renders current state and translates controls into narrow callbacks.
@MainActor
final class SettingsWindowController: NSWindowController {
    enum Section: Int, CaseIterable {
        case general
        case screenshots
        case recording

        var title: String {
            switch self {
            case .general: "General"
            case .screenshots: "Screenshots"
            case .recording: "Recording"
            }
        }
    }

    private static let labelColumnWidth: CGFloat = 170

    private let screenshotPreferences: ScreenshotPreferences
    private let sectionSelector = NSSegmentedControl(
        labels: Section.allCases.map(\.title),
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let pageContainer = NSView()
    private var pageViews: [Section: NSView] = [:]

    private let destinationLabel = NSTextField(labelWithString: "")
    private let chooseDestinationButton = NSButton(
        title: "Change…", target: nil, action: nil)
    private let hideNotificationsCheckbox = NSButton(
        checkboxWithTitle: "Hide notifications from capture", target: nil, action: nil)
    private let hideMenuBarCheckbox = NSButton(
        checkboxWithTitle: "Hide menu bar, including the clock", target: nil, action: nil)
    private let hideDesktopItemsCheckbox = NSButton(
        checkboxWithTitle: "Hide Desktop items from capture", target: nil, action: nil)
    private let launchAtLoginCheckbox = NSButton(
        checkboxWithTitle: "Open Record at Login", target: nil, action: nil)

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
    private let screenshotMessageLabel = NSTextField(wrappingLabelWithString: "")
    private var shortcutButtons: [ScreenshotCaptureKind: ShortcutRecorderButton] = [:]

    private let renameRecordingCheckbox = NSButton(
        checkboxWithTitle: "Rename finished recordings", target: nil, action: nil)
    private let recordingTemplateLabel = NSTextField(labelWithString: "")
    private let editRecordingTemplateButton = NSButton(
        title: "Edit…", target: nil, action: nil)
    private let transcriptionPopup = NSPopUpButton()
    private let parakeetStatusLabel = NSTextField(labelWithString: "")
    private let parakeetSetupButton = NSButton(
        title: "Set Up Parakeet Model…", target: nil, action: nil)
    private let transcriptRefinementCheckbox = NSButton(
        checkboxWithTitle: "Improve Transcript Readability", target: nil, action: nil)

    var onChooseExportFolder: (() -> Void)?
    var onScreenshotPreferencesChanged: (() -> Void)?
    var onToggleCapturePrivacy: ((CapturePrivacyFeature) -> Void)?
    var onToggleLaunchAtLogin: (() -> Void)?
    var onToggleRecordingName: (() -> Void)?
    var onEditRecordingNameTemplate: (() -> Void)?
    var onSelectTranscriptionEngine: ((TranscriptionEngineOption) -> Void)?
    var onSetUpParakeetModel: (() -> Void)?
    var onToggleTranscriptRefinement: (() -> Void)?

    var selectedSection: Section {
        Section(rawValue: sectionSelector.selectedSegment) ?? .general
    }
    var isMacWhisperOptionVisible: Bool {
        transcriptionPopup.itemArray.first {
            $0.representedObject as? String == TranscriptionEngineOption.macwhisper.rawValue
        }?.isHidden == false
    }
    var isTranscriptRefinementSelected: Bool {
        transcriptRefinementCheckbox.state == .on
    }
    var isTranscriptRefinementEnabled: Bool {
        transcriptRefinementCheckbox.isEnabled
    }
    var isDestinationSelectionEnabled: Bool { chooseDestinationButton.isEnabled }
    var parakeetSetupButtonTitle: String { parakeetSetupButton.title }
    var isParakeetSetupButtonEnabled: Bool { parakeetSetupButton.isEnabled }
    var parakeetStatus: String { parakeetStatusLabel.stringValue }
    var areCapturePrivacyControlsEnabled: Bool {
        hideNotificationsCheckbox.isEnabled
            && hideMenuBarCheckbox.isEnabled
            && hideDesktopItemsCheckbox.isEnabled
    }

    init(screenshotPreferences: ScreenshotPreferences) {
        self.screenshotPreferences = screenshotPreferences
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 500),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Record Settings"
        window.contentMinSize = NSSize(width: 720, height: 500)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildUI()
        refreshScreenshotPreferences()
        select(section: .general)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func show(exportDirectory: URL) {
        updateExportDirectory(exportDirectory)
        refreshScreenshotPreferences()
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func select(section: Section) {
        sectionSelector.selectedSegment = section.rawValue
        for (candidate, view) in pageViews {
            view.isHidden = candidate != section
        }
    }

    func updateExportDirectory(_ url: URL) {
        destinationLabel.stringValue = url.path
        destinationLabel.toolTip = url.path
    }

    func updateInteractionAvailability(_ availability: SettingsInteractionAvailability) {
        chooseDestinationButton.isEnabled = availability.destinationSelectionEnabled
        for checkbox in [
            hideNotificationsCheckbox,
            hideMenuBarCheckbox,
            hideDesktopItemsCheckbox,
        ] {
            checkbox.isEnabled = availability.capturePrivacyEnabled
        }
    }

    func updateCapturePrivacy(_ configuration: CapturePrivacyConfiguration) {
        hideNotificationsCheckbox.state = configuration.hideNotifications ? .on : .off
        hideMenuBarCheckbox.state = configuration.hideMenuBar ? .on : .off
        hideDesktopItemsCheckbox.state = configuration.hideDesktopItems ? .on : .off
    }

    func updateLaunchAtLogin(_ state: LaunchAtLoginState) {
        launchAtLoginCheckbox.allowsMixedState = true
        launchAtLoginCheckbox.isEnabled = state != .unavailable
        launchAtLoginCheckbox.state =
            switch state {
            case .disabled, .unavailable: .off
            case .enabled: .on
            case .requiresApproval: .mixed
            }
        launchAtLoginCheckbox.toolTip =
            switch state {
            case .disabled: "Open Record automatically after you sign in"
            case .enabled: "Record will open automatically after you sign in"
            case .requiresApproval: "Click to approve Record in Login Items"
            case .unavailable: "Open at Login is unavailable for this copy of Record"
            }
    }

    func updateRecordingName(enabled: Bool, template: String) {
        renameRecordingCheckbox.state = enabled ? .on : .off
        recordingTemplateLabel.stringValue = template
        recordingTemplateLabel.toolTip = template
        editRecordingTemplateButton.isEnabled = enabled
    }

    func updateTranscriptionEngine(
        _ engine: TranscriptionEngineOption,
        macWhisperAvailable: Bool,
        parakeetModelAvailable: Bool,
        parakeetSetupInProgress: Bool = false
    ) {
        for item in transcriptionPopup.itemArray {
            let option = item.representedObject as? String
            item.isHidden =
                option == TranscriptionEngineOption.macwhisper.rawValue
                && !macWhisperAvailable
        }
        if let item = transcriptionPopup.itemArray.first(where: {
            $0.representedObject as? String == engine.rawValue
        }) {
            transcriptionPopup.select(item)
        }
        parakeetStatusLabel.stringValue =
            if parakeetModelAvailable {
                "Installed"
            } else if parakeetSetupInProgress {
                "Downloading and verifying…"
            } else {
                "Setup required"
            }
        parakeetStatusLabel.textColor =
            parakeetModelAvailable ? .secondaryLabelColor : .systemOrange
        parakeetSetupButton.isHidden = parakeetModelAvailable
        parakeetSetupButton.isEnabled = !parakeetSetupInProgress
        parakeetSetupButton.title =
            parakeetSetupInProgress ? "Downloading…" : "Set Up Parakeet Model…"
    }

    func updateTranscriptRefinement(enabled: Bool, available: Bool, detail: String) {
        transcriptRefinementCheckbox.state = enabled ? .on : .off
        transcriptRefinementCheckbox.isEnabled = available
        transcriptRefinementCheckbox.toolTip = detail
    }

    func showShortcutRegistrationFailures(
        _ failures: [GlobalScreenshotShortcutFailure]
    ) {
        guard !failures.isEmpty else {
            screenshotMessageLabel.stringValue = ""
            return
        }
        let names = failures.map(\.kind.displayName).joined(separator: ", ")
        screenshotMessageLabel.stringValue =
            "Couldn’t register: \(names). Another app or macOS is using the shortcut."
    }

    private func buildUI() {
        guard let contentView = window?.contentView else { return }
        sectionSelector.target = self
        sectionSelector.action = #selector(sectionChanged)
        sectionSelector.translatesAutoresizingMaskIntoConstraints = false
        sectionSelector.setAccessibilityLabel("Settings Section")

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        pageContainer.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(sectionSelector)
        contentView.addSubview(separator)
        contentView.addSubview(pageContainer)

        pageViews = [
            .general: buildGeneralPage(),
            .screenshots: buildScreenshotsPage(),
            .recording: buildRecordingPage(),
        ]
        for view in pageViews.values {
            view.translatesAutoresizingMaskIntoConstraints = false
            pageContainer.addSubview(view)
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: pageContainer.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: pageContainer.trailingAnchor),
                view.topAnchor.constraint(equalTo: pageContainer.topAnchor),
                view.bottomAnchor.constraint(equalTo: pageContainer.bottomAnchor),
            ])
        }

        NSLayoutConstraint.activate([
            sectionSelector.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 18),
            sectionSelector.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            sectionSelector.widthAnchor.constraint(greaterThanOrEqualToConstant: 360),
            separator.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            separator.topAnchor.constraint(equalTo: sectionSelector.bottomAnchor, constant: 14),
            pageContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            pageContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            pageContainer.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 8),
            pageContainer.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }

    private func buildGeneralPage() -> NSView {
        makePage(
            title: "General",
            description: "Shared preferences for screenshots and finished recordings."
        ) { stack in
            stack.addArrangedSubview(sectionHeading("Files"))
            chooseDestinationButton.target = self
            chooseDestinationButton.action = #selector(chooseExportFolder)
            destinationLabel.lineBreakMode = .byTruncatingMiddle
            destinationLabel.setContentCompressionResistancePriority(
                .defaultLow, for: .horizontal)
            stack.addArrangedSubview(
                row(label: "Save to", views: [destinationLabel, chooseDestinationButton]))
            stack.addArrangedSubview(
                note(
                    "Screenshots and completed screen or audio recordings use this one approved folder."
                ))

            stack.addArrangedSubview(sectionHeading("Capture Privacy"))
            configurePrivacyCheckbox(
                hideNotificationsCheckbox,
                feature: .notifications,
                toolTip:
                    "Capture-only. Notification sounds can still be recorded unless Focus is enabled."
            )
            configurePrivacyCheckbox(
                hideMenuBarCheckbox,
                feature: .menuBar,
                toolTip: "Capture-only. Does not change macOS menu bar preferences."
            )
            configurePrivacyCheckbox(
                hideDesktopItemsCheckbox,
                feature: .desktopItems,
                toolTip: "Capture-only. Existing Finder windows remain visible."
            )
            for checkbox in [
                hideNotificationsCheckbox,
                hideMenuBarCheckbox,
                hideDesktopItemsCheckbox,
            ] {
                stack.addArrangedSubview(row(label: "", views: [checkbox]))
            }
            stack.addArrangedSubview(
                note("These exclusions apply to screenshots and screen recordings."))

            stack.addArrangedSubview(sectionHeading("Startup"))
            launchAtLoginCheckbox.target = self
            launchAtLoginCheckbox.action = #selector(toggleLaunchAtLogin)
            stack.addArrangedSubview(row(label: "", views: [launchAtLoginCheckbox]))
        }
    }

    private func buildScreenshotsPage() -> NSView {
        makePage(
            title: "Screenshots",
            description:
                "Captures save immediately to the shared folder and copy a lossless PNG to the clipboard."
        ) { stack in
            stack.addArrangedSubview(sectionHeading("Image"))
            formatPopup.addItems(withTitles: ScreenshotImageFormat.allCases.map(\.displayName))
            formatPopup.target = self
            formatPopup.action = #selector(formatChanged)
            stack.addArrangedSubview(row(label: "Format", views: [formatPopup]))

            qualitySlider.numberOfTickMarks = 11
            qualitySlider.allowsTickMarkValuesOnly = false
            qualitySlider.target = self
            qualitySlider.action = #selector(qualityChanged)
            qualitySlider.translatesAutoresizingMaskIntoConstraints = false
            qualitySlider.widthAnchor.constraint(equalToConstant: 220).isActive = true
            stack.addArrangedSubview(
                row(label: "JPEG quality", views: [qualitySlider, qualityLabel]))

            soundCheckbox.target = self
            soundCheckbox.action = #selector(soundChanged)
            stack.addArrangedSubview(row(label: "Feedback", views: [soundCheckbox]))

            stack.addArrangedSubview(sectionHeading("Global Shortcuts"))
            for kind in ScreenshotCaptureKind.allCases {
                let button = ShortcutRecorderButton(kind: kind)
                button.onRecord = { [weak self] shortcut in
                    self?.storeShortcut(shortcut, for: kind)
                }
                button.onInvalid = { [weak self] message in
                    self?.screenshotMessageLabel.stringValue = message
                }
                shortcutButtons[kind] = button
                stack.addArrangedSubview(row(label: kind.displayName, views: [button]))
            }

            let reset = NSButton(
                title: "Restore Defaults",
                target: self,
                action: #selector(restoreScreenshotDefaults)
            )
            let systemShortcuts = NSButton(
                title: "Open macOS Keyboard Shortcuts…",
                target: self,
                action: #selector(openSystemShortcuts)
            )
            stack.addArrangedSubview(row(label: "", views: [reset, systemShortcuts]))

            screenshotMessageLabel.textColor = .systemOrange
            screenshotMessageLabel.maximumNumberOfLines = 2
            stack.addArrangedSubview(screenshotMessageLabel)
        }
    }

    private func buildRecordingPage() -> NSView {
        makePage(
            title: "Recording",
            description:
                "Configure finished recording names and the local transcription workflow."
        ) { stack in
            stack.addArrangedSubview(sectionHeading("File Names"))
            renameRecordingCheckbox.target = self
            renameRecordingCheckbox.action = #selector(toggleRecordingName)
            stack.addArrangedSubview(row(label: "", views: [renameRecordingCheckbox]))

            recordingTemplateLabel.lineBreakMode = .byTruncatingMiddle
            recordingTemplateLabel.setContentCompressionResistancePriority(
                .defaultLow, for: .horizontal)
            editRecordingTemplateButton.target = self
            editRecordingTemplateButton.action = #selector(editRecordingNameTemplate)
            stack.addArrangedSubview(
                row(
                    label: "Template",
                    views: [recordingTemplateLabel, editRecordingTemplateButton]
                ))

            stack.addArrangedSubview(sectionHeading("Transcription"))
            transcriptionPopup.addItems(withTitles: [
                "Parakeet (Default)",
                "MacWhisper (Small)",
            ])
            transcriptionPopup.itemArray[0].representedObject =
                TranscriptionEngineOption.parakeet.rawValue
            transcriptionPopup.itemArray[1].representedObject =
                TranscriptionEngineOption.macwhisper.rawValue
            transcriptionPopup.target = self
            transcriptionPopup.action = #selector(transcriptionEngineChanged)
            stack.addArrangedSubview(row(label: "Model", views: [transcriptionPopup]))

            parakeetSetupButton.target = self
            parakeetSetupButton.action = #selector(setUpParakeetModel)
            stack.addArrangedSubview(
                row(label: "Parakeet", views: [parakeetStatusLabel, parakeetSetupButton]))

            transcriptRefinementCheckbox.target = self
            transcriptRefinementCheckbox.action = #selector(toggleTranscriptRefinement)
            stack.addArrangedSubview(
                row(label: "On-device", views: [transcriptRefinementCheckbox]))
            stack.addArrangedSubview(
                note(
                    "Retry Failed Transcription remains in the Record menu only when a failed job is actionable."
                ))
        }
    }

    private func makePage(
        title: String,
        description: String,
        build: (NSStackView) -> Void
    ) -> NSView {
        let page = NSView()
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 11
        stack.translatesAutoresizingMaskIntoConstraints = false
        page.addSubview(stack)

        let heading = NSTextField(labelWithString: title)
        heading.font = .systemFont(ofSize: 22, weight: .semibold)
        stack.addArrangedSubview(heading)
        let descriptionLabel = NSTextField(wrappingLabelWithString: description)
        descriptionLabel.maximumNumberOfLines = 2
        stack.addArrangedSubview(descriptionLabel)
        build(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: page.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: page.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: page.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: page.bottomAnchor, constant: -20),
        ])
        return page
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
        labelView.widthAnchor.constraint(equalToConstant: Self.labelColumnWidth).isActive = true
        labelView.setContentCompressionResistancePriority(.required, for: .horizontal)
        row.addArrangedSubview(labelView)
        for view in views { row.addArrangedSubview(view) }
        return row
    }

    private func sectionHeading(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        return label
    }

    private func note(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.textColor = .secondaryLabelColor
        label.maximumNumberOfLines = 2
        return label
    }

    private func configurePrivacyCheckbox(
        _ checkbox: NSButton,
        feature: CapturePrivacyFeature,
        toolTip: String
    ) {
        checkbox.identifier = NSUserInterfaceItemIdentifier(feature.rawValue)
        checkbox.target = self
        checkbox.action = #selector(toggleCapturePrivacy)
        checkbox.toolTip = toolTip
    }

    private func refreshScreenshotPreferences() {
        formatPopup.selectItem(at: screenshotPreferences.format == .png ? 0 : 1)
        qualitySlider.doubleValue = screenshotPreferences.jpegQuality
        qualityLabel.stringValue =
            "\(Int((screenshotPreferences.jpegQuality * 100).rounded()))%"
        qualitySlider.isEnabled = screenshotPreferences.format == .jpeg
        qualityLabel.textColor =
            screenshotPreferences.format == .jpeg ? .labelColor : .secondaryLabelColor
        soundCheckbox.state = screenshotPreferences.playShutterSound ? .on : .off
        let shortcuts = screenshotPreferences.shortcuts
        for kind in ScreenshotCaptureKind.allCases {
            shortcutButtons[kind]?.update(shortcut: shortcuts[kind])
        }
    }

    private func storeShortcut(
        _ shortcut: ScreenshotShortcut?,
        for kind: ScreenshotCaptureKind
    ) {
        do {
            try screenshotPreferences.setShortcut(shortcut, for: kind)
            screenshotMessageLabel.stringValue = ""
            refreshScreenshotPreferences()
            onScreenshotPreferencesChanged?()
        } catch ScreenshotCaptureContractError.duplicateShortcut {
            screenshotMessageLabel.stringValue =
                "That shortcut is already assigned to another screenshot command."
            NSSound.beep()
            refreshScreenshotPreferences()
        } catch {
            screenshotMessageLabel.stringValue = "That shortcut can’t be saved."
            NSSound.beep()
            refreshScreenshotPreferences()
        }
    }

    @objc private func sectionChanged() {
        select(section: Section(rawValue: sectionSelector.selectedSegment) ?? .general)
    }

    @objc private func chooseExportFolder() { onChooseExportFolder?() }

    @objc private func toggleCapturePrivacy(_ sender: NSButton) {
        guard let rawValue = sender.identifier?.rawValue,
            let feature = CapturePrivacyFeature(rawValue: rawValue)
        else { return }
        onToggleCapturePrivacy?(feature)
    }

    @objc private func toggleLaunchAtLogin() { onToggleLaunchAtLogin?() }
    @objc private func toggleRecordingName() { onToggleRecordingName?() }
    @objc private func editRecordingNameTemplate() { onEditRecordingNameTemplate?() }

    @objc private func transcriptionEngineChanged() {
        guard
            let rawValue = transcriptionPopup.selectedItem?.representedObject as? String,
            let engine = TranscriptionEngineOption(rawValue: rawValue)
        else { return }
        onSelectTranscriptionEngine?(engine)
    }

    @objc private func setUpParakeetModel() { onSetUpParakeetModel?() }
    @objc private func toggleTranscriptRefinement() { onToggleTranscriptRefinement?() }

    @objc private func formatChanged() {
        screenshotPreferences.format = formatPopup.indexOfSelectedItem == 0 ? .png : .jpeg
        refreshScreenshotPreferences()
        onScreenshotPreferencesChanged?()
    }

    @objc private func qualityChanged() {
        screenshotPreferences.jpegQuality = qualitySlider.doubleValue
        refreshScreenshotPreferences()
        onScreenshotPreferencesChanged?()
    }

    @objc private func soundChanged() {
        screenshotPreferences.playShutterSound = soundCheckbox.state == .on
        onScreenshotPreferencesChanged?()
    }

    @objc private func restoreScreenshotDefaults() {
        screenshotPreferences.restoreDefaultShortcuts()
        refreshScreenshotPreferences()
        onScreenshotPreferencesChanged?()
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
