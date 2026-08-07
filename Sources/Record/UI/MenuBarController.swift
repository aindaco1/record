import AppKit
import RecordCore

/// Status bar item in the top-right of the menu bar. Shows recording state at
/// a glance and provides the only persistent control surface for the daemon
/// (since we run as `.accessory` — no dock icon, no main window).
@MainActor
final class MenuBarController {
    private let statusItem: NSStatusItem
    private let stateLabel: NSMenuItem
    private let transcriptionLabel: NSMenuItem
    private let toggleItem: NSMenuItem
    private let audioOnlyItem: NSMenuItem
    private let screenRecordingPermissionItem: NSMenuItem
    private let hideNotificationsItem: NSMenuItem
    private let hideMenuBarItem: NSMenuItem
    private let hideDesktopItemsItem: NSMenuItem
    private let recordingNameItem: NSMenuItem
    private let recordingNameTemplateItem: NSMenuItem
    private let gifskiItem: NSMenuItem
    private let transcriptionEngineItem: NSMenuItem
    private let parakeetEngineItem: NSMenuItem
    private let macWhisperEngineItem: NSMenuItem
    private let exportFolderItem: NSMenuItem
    private let restartItem: NSMenuItem
    private var isRecording = false

    var onToggle: (() -> Void)?
    var onStartAudioOnly: (() -> Void)?
    var onManageScreenRecordingPermission: (() -> Void)?
    var onToggleCapturePrivacy: ((CapturePrivacyFeature) -> Void)?
    var onToggleRecordingName: (() -> Void)?
    var onEditRecordingNameTemplate: (() -> Void)?
    var onOpenLastVideoInGifski: (() -> Void)?
    var onSelectTranscriptionEngine: ((TranscriptionEngineOption) -> Void)?
    var onOpenFolder: (() -> Void)?
    var onChooseExportFolder: (() -> Void)?
    var onRestart: (() -> Void)?
    var onQuit: (() -> Void)?

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        let menu = NSMenu()
        menu.autoenablesItems = false

        stateLabel = NSMenuItem(title: "idle", action: nil, keyEquivalent: "")
        stateLabel.isEnabled = false
        menu.addItem(stateLabel)

        transcriptionLabel = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        transcriptionLabel.isEnabled = false
        transcriptionLabel.isHidden = true
        menu.addItem(transcriptionLabel)

        menu.addItem(.separator())

        toggleItem = NSMenuItem(
            title: "Start screen recording",
            action: #selector(toggleClicked),
            keyEquivalent: "r"
        )
        menu.addItem(toggleItem)

        audioOnlyItem = NSMenuItem(
            title: "Start audio-only recording",
            action: #selector(audioOnlyClicked),
            keyEquivalent: ""
        )
        menu.addItem(audioOnlyItem)

        screenRecordingPermissionItem = NSMenuItem(
            title: "Set Up Recording Permissions…",
            action: #selector(manageScreenRecordingPermissionClicked),
            keyEquivalent: ""
        )
        menu.addItem(screenRecordingPermissionItem)

        let pluginsItem = NSMenuItem(title: "Plugins", action: nil, keyEquivalent: "")
        let pluginsMenu = NSMenu(title: "Plugins")
        pluginsMenu.autoenablesItems = false
        hideNotificationsItem = Self.privacyMenuItem(
            title: "Hide Notifications from Capture",
            feature: .notifications,
            toolTip:
                "Capture-only. Notification sounds can still be recorded unless Focus is enabled."
        )
        pluginsMenu.addItem(hideNotificationsItem)
        hideMenuBarItem = Self.privacyMenuItem(
            title: "Hide Menu Bar (including Clock)",
            feature: .menuBar,
            toolTip: "Capture-only. Does not change SystemUIServer or macOS preferences."
        )
        pluginsMenu.addItem(hideMenuBarItem)
        hideDesktopItemsItem = Self.privacyMenuItem(
            title: "Hide Desktop Items from Capture",
            feature: .desktopItems,
            toolTip: "Capture-only. Existing Finder windows remain visible."
        )
        pluginsMenu.addItem(hideDesktopItemsItem)
        pluginsMenu.addItem(.separator())
        recordingNameItem = NSMenuItem(
            title: "Rename Finished Recording",
            action: #selector(toggleRecordingNameClicked),
            keyEquivalent: ""
        )
        pluginsMenu.addItem(recordingNameItem)
        recordingNameTemplateItem = NSMenuItem(
            title: "Recording Name Template…",
            action: #selector(editRecordingNameTemplateClicked),
            keyEquivalent: ""
        )
        pluginsMenu.addItem(recordingNameTemplateItem)
        pluginsMenu.addItem(.separator())
        gifskiItem = NSMenuItem(
            title: "Open Last Video in Gifski",
            action: #selector(openLastVideoInGifskiClicked),
            keyEquivalent: ""
        )
        pluginsMenu.addItem(gifskiItem)
        pluginsItem.submenu = pluginsMenu
        menu.addItem(pluginsItem)

        transcriptionEngineItem = NSMenuItem(
            title: "Transcription: Parakeet",
            action: nil,
            keyEquivalent: ""
        )
        let transcriptionMenu = NSMenu(title: "Transcription")
        transcriptionMenu.autoenablesItems = false
        parakeetEngineItem = NSMenuItem(
            title: "Parakeet (Default)",
            action: #selector(transcriptionEngineClicked),
            keyEquivalent: ""
        )
        parakeetEngineItem.representedObject = TranscriptionEngineOption.parakeet.rawValue
        transcriptionMenu.addItem(parakeetEngineItem)
        macWhisperEngineItem = NSMenuItem(
            title: "MacWhisper (Small)",
            action: #selector(transcriptionEngineClicked),
            keyEquivalent: ""
        )
        macWhisperEngineItem.representedObject =
            TranscriptionEngineOption.macwhisper.rawValue
        transcriptionMenu.addItem(macWhisperEngineItem)
        transcriptionEngineItem.submenu = transcriptionMenu
        menu.addItem(transcriptionEngineItem)

        let openFolder = NSMenuItem(
            title: "Open session storage",
            action: #selector(openFolderClicked),
            keyEquivalent: "o"
        )
        menu.addItem(openFolder)

        exportFolderItem = NSMenuItem(
            title: "Export folder: Desktop…",
            action: #selector(chooseExportFolderClicked),
            keyEquivalent: ""
        )
        menu.addItem(exportFolderItem)

        menu.addItem(.separator())

        restartItem = NSMenuItem(
            title: "Restart Record",
            action: #selector(restartClicked),
            keyEquivalent: ""
        )
        menu.addItem(restartItem)

        let quit = NSMenuItem(
            title: "Quit Record",
            action: #selector(quitClicked),
            keyEquivalent: "q"
        )
        menu.addItem(quit)

        for item in [
            toggleItem,
            audioOnlyItem,
            screenRecordingPermissionItem,
            hideNotificationsItem,
            hideMenuBarItem,
            hideDesktopItemsItem,
            recordingNameItem,
            recordingNameTemplateItem,
            gifskiItem,
            parakeetEngineItem,
            macWhisperEngineItem,
            openFolder,
            exportFolderItem,
            restartItem,
            quit,
        ] {
            item.target = self
        }

        statusItem.menu = menu

        if let button = statusItem.button {
            button.image = Self.menuBarImage()
            button.imagePosition = .imageLeft
        }
    }

    /// Reflect recording state in the icon tint and menu item titles. The
    /// menu bar shows only the Record ring (red while recording); the elapsed
    /// counter lives in the menu's state label. Call once a second while
    /// recording.
    func update(recording: Bool, elapsed: String?, mode: RecordingMode = .screen) {
        isRecording = recording
        stateLabel.title =
            recording
            ? "● \(mode.displayName) recording · \(elapsed ?? "0:00")"
            : "idle"
        toggleItem.title = recording ? "Stop recording" : "Start screen recording"
        toggleItem.isEnabled = true
        audioOnlyItem.isEnabled = !recording
        screenRecordingPermissionItem.isEnabled = !recording
        restartItem.isEnabled = !recording
        setCapturePrivacyItemsEnabled(!recording)
        statusItem.button?.contentTintColor = recording ? .systemRed : nil
    }

    func updatePreparingScreenRecording() {
        stateLabel.title = "preparing screen recording…"
        toggleItem.title = "Preparing screen recording…"
        toggleItem.isEnabled = false
        audioOnlyItem.isEnabled = false
        screenRecordingPermissionItem.isEnabled = false
        restartItem.isEnabled = false
        setCapturePrivacyItemsEnabled(false)
        statusItem.button?.contentTintColor = .systemOrange
    }

    func updateStoppingRecording() {
        stateLabel.title = "stopping recording…"
        toggleItem.title = "Stopping recording…"
        toggleItem.isEnabled = false
        audioOnlyItem.isEnabled = false
        screenRecordingPermissionItem.isEnabled = false
        restartItem.isEnabled = false
        setCapturePrivacyItemsEnabled(false)
    }

    func updateScreenRecordingPermission(
        _ presentation: ScreenRecordingPermissionPresentation
    ) {
        screenRecordingPermissionItem.title = presentation.menuTitle
        screenRecordingPermissionItem.toolTip = presentation.menuToolTip
        screenRecordingPermissionItem.state = presentation.isGranted ? .on : .off
        screenRecordingPermissionItem.isEnabled = !isRecording
    }

    func updateCapturePrivacy(_ configuration: CapturePrivacyConfiguration) {
        hideNotificationsItem.state = configuration.hideNotifications ? .on : .off
        hideMenuBarItem.state = configuration.hideMenuBar ? .on : .off
        hideDesktopItemsItem.state = configuration.hideDesktopItems ? .on : .off
    }

    func updateRecordingName(enabled: Bool, template: String) {
        recordingNameItem.state = enabled ? .on : .off
        recordingNameTemplateItem.isEnabled = enabled
        recordingNameTemplateItem.toolTip = template
    }

    func updateGifski(available: Bool, hasFinishedVideo: Bool) {
        gifskiItem.isEnabled = available && hasFinishedVideo
        gifskiItem.title =
            available
            ? "Open Last Video in Gifski"
            : "Gifski Not Installed"
    }

    /// Show transcription progress/failure as a second status line in the
    /// menu; nil hides it. Independent of recording state — a new recording
    /// can run while the last one transcribes.
    func updateTranscription(_ text: String?) {
        transcriptionLabel.title = text ?? ""
        transcriptionLabel.isHidden = text == nil
    }

    func updateTranscriptionEngine(
        _ engine: TranscriptionEngineOption,
        macWhisperAvailable: Bool
    ) {
        transcriptionEngineItem.title = "Transcription: \(engine.displayName)"
        parakeetEngineItem.state = engine == .parakeet ? .on : .off
        macWhisperEngineItem.state = engine == .macwhisper ? .on : .off
        macWhisperEngineItem.isEnabled = macWhisperAvailable
        macWhisperEngineItem.title =
            macWhisperAvailable
            ? "MacWhisper (Small)"
            : "MacWhisper (helper unavailable)"
        macWhisperEngineItem.toolTip =
            macWhisperAvailable
            ? "Uses the installed local MacWhisper Small model"
            : "Run scripts/setup/install-macwhisper-cli.sh first"
    }

    /// Show the default or approved destination for finished exports. An
    /// ellipsis communicates that selecting the item opens a folder picker.
    func updateExportDirectory(_ url: URL) {
        exportFolderItem.title = "Export folder: \(url.lastPathComponent)…"
        exportFolderItem.toolTip = url.path
    }

    // NewKap's MIT-licensed 2x menu-bar ring is embedded to preserve Record's
    // single-binary LaunchAgent installation. Provenance lives in
    // THIRD_PARTY_NOTICES.md.
    private static let menuBarImageBase64 = """
        iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAAAXNSR0IArs4c6QAAAzNJREFU
        WAnFl89rE0EUx+fNJqkYCYgetPYSEAVBwYNQKaUpUWgqiEVz0Xv+AK8WD6JX/4Dc7SWViqDx
        kNJUKRZ66EEoCEIvMXpQhNAU82N3fN/ZTEhrYiZZSwJp0sl738/bmdk33yVh+Uqn05HSj1+z
        5InbisQlUmJcEL/xUqLMY2Ue21FSvJ44fXItl8vVbaSpX1AiMX+mTvXHyqMHTIr1i/d/pwpJ
        9SKiIk+Kxbff/5XTs4BUKjVW+d185CnxUCgVhQgHb5OkV0LKDyScryE3WsZ406mOK+GeE543
        rTx1RwlxFeOCqCpJPI8dCz3L5/M1PXboT9cC9FWLxopSatLXoWUiZ3Fj7d3nQ/ld/52anbu
        olPuU8++18jcjIrzQbTb+KmA6OXel6bpv+Kon+BJ2Jan7G8XCZldSn8GpxI1JT9ESL12cZ6
        MUDqn594XCp860AwXgymuisaXhROvHnRN3V1dXfnYmDPo9mVw4te/uvWTNGRQxJsLXOmdCGk
        GseZ2n3cAvX4jfDAqHNjSgxfB1aIMBluG2C8CG89ecdnHl2Wy2YYKCfkILmlhSMMAymnoJWl
        P/hSuM8q69PuyaG9Fen/6eEB9xd/BSnMdS6BnAfQ44ES0fFRxFQRsMsDSTxyQ6nN9kcNs6i
        72q/1/jhgEm2BLtFR2O12Lb9j4PUgwYYIEJtkRvh6DucEGUB8g1LLAlDhady+11AI1goS0W
        2Nzo/BMNvT2Yqn22YYEtzZFqDhZ7meEj2yw+ztuNqBGr6Z4wvKx9ZpulBNsHNhNIpWrzrL1
        EsMgO1jdsQl2APs+D6VpnGxbY2IQ7OpPNhLVC0MAWC2wJDwc9OJmgurb5hgW2hIHkHVCBjY
        KTsRUZNk67JW3ZqAK2hHuFgYQgbNSwwrZ5hgEm2Po2hHvFEQkPhyPTVmzQOGiDAZZmsoAuQ
        J/L7F4hCA8HGzWoeL94aPr+kKHMMras3YhgnfmsZvOp4vBwmUwm3E/U9ndoaV/I2mCAZXIP
        dL+RmlJUhGkJOc4tXqMS78iZ/ebeVpA9gVxoQAuasOVm6rvOgBkc6YOJKWKkj2amCHzq2Rj
        Fw2lnEfh+VI/nfwA+auCbxANjCwAAAABJRU5ErkJggg==
        """

    static func menuBarImage() -> NSImage? {
        guard
            let data = Data(
                base64Encoded: menuBarImageBase64,
                options: .ignoreUnknownCharacters
            ),
            let image = NSImage(data: data)
        else { return nil }
        image.isTemplate = true
        image.size = NSSize(width: 16, height: 16)
        return image
    }

    private static func privacyMenuItem(
        title: String,
        feature: CapturePrivacyFeature,
        toolTip: String
    ) -> NSMenuItem {
        let item = NSMenuItem(
            title: title,
            action: #selector(toggleCapturePrivacyClicked),
            keyEquivalent: ""
        )
        item.representedObject = feature.rawValue
        item.toolTip = toolTip
        return item
    }

    private func setCapturePrivacyItemsEnabled(_ enabled: Bool) {
        hideNotificationsItem.isEnabled = enabled
        hideMenuBarItem.isEnabled = enabled
        hideDesktopItemsItem.isEnabled = enabled
    }

    @objc private func toggleClicked() { onToggle?() }
    @objc private func audioOnlyClicked() { onStartAudioOnly?() }
    @objc private func manageScreenRecordingPermissionClicked() {
        onManageScreenRecordingPermission?()
    }
    @objc private func toggleCapturePrivacyClicked(_ sender: NSMenuItem) {
        guard
            let rawValue = sender.representedObject as? String,
            let feature = CapturePrivacyFeature(rawValue: rawValue)
        else { return }
        onToggleCapturePrivacy?(feature)
    }
    @objc private func toggleRecordingNameClicked() { onToggleRecordingName?() }
    @objc private func editRecordingNameTemplateClicked() { onEditRecordingNameTemplate?() }
    @objc private func openLastVideoInGifskiClicked() { onOpenLastVideoInGifski?() }
    @objc private func transcriptionEngineClicked(_ sender: NSMenuItem) {
        guard
            let rawValue = sender.representedObject as? String,
            let engine = TranscriptionEngineOption(rawValue: rawValue)
        else { return }
        onSelectTranscriptionEngine?(engine)
    }
    @objc private func openFolderClicked() { onOpenFolder?() }
    @objc private func chooseExportFolderClicked() { onChooseExportFolder?() }
    @objc private func restartClicked() { onRestart?() }
    @objc private func quitClicked() { onQuit?() }
}
