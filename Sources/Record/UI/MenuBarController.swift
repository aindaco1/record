import AppKit
import QuartzCore
import RecordCore

/// Status bar item in the top-right of the menu bar. Shows recording state at
/// a glance and provides the only persistent control surface for the daemon
/// (since we run as `.accessory` — no dock icon, no main window).
@MainActor
final class MenuBarController {
    static let recordingPulseAnimationKey = "record.recording-pulse"
    static let transcriptionModelMenuTitle = "Transcript model"
    static let transcriptRefinementMenuTitle = "Improve Transcript Readability"
    static let openTempSessionMenuTitle = "Open temp session"
    static let openLastRecordingMenuTitle = "Open last recording"
    static let exportFolderMenuTitle = "Select export folder…"
    static let checkForUpdatesMenuTitle = "Check for Updates…"
    static let launchAtLoginMenuTitle = "Open at Login"
    static let screenSourceMenuTitle = "Screen source"

    private let statusItem: NSStatusItem
    private let stateLabel: NSMenuItem
    private let transcriptionLabel: NSMenuItem
    private let toggleItem: NSMenuItem
    private let pauseResumeItem: NSMenuItem
    private let audioOnlyItem: NSMenuItem
    private let screenSourceItem: NSMenuItem
    private let mainDisplaySourceItem: NSMenuItem
    private let systemPickerSourceItem: NSMenuItem
    private let regionSourceItem: NSMenuItem
    private let hideNotificationsItem: NSMenuItem
    private let hideMenuBarItem: NSMenuItem
    private let hideDesktopItemsItem: NSMenuItem
    private let recordingNameItem: NSMenuItem
    private let recordingNameTemplateItem: NSMenuItem
    private let gifskiItem: NSMenuItem
    private let transcriptionEngineItem: NSMenuItem
    private let parakeetEngineItem: NSMenuItem
    private let macWhisperEngineItem: NSMenuItem
    private let transcriptRefinementItem: NSMenuItem
    private let parakeetModelSetupItem: NSMenuItem
    private let retryTranscriptionItem: NSMenuItem
    private let openLastRecordingItem: NSMenuItem
    private let exportFolderItem: NSMenuItem
    private let checkForUpdatesItem: NSMenuItem
    private let launchAtLoginItem: NSMenuItem
    private var recordingIndicatorIsActive = false
    private var captureHealthNote: String?

    var isMacWhisperMenuItemVisible: Bool { !macWhisperEngineItem.isHidden }
    var isTranscriptRefinementSelected: Bool { transcriptRefinementItem.state == .on }
    var isTranscriptRefinementEnabled: Bool { transcriptRefinementItem.isEnabled }
    var canDispatchTranscriptRefinementAction: Bool {
        transcriptRefinementItem.target === self
            && transcriptRefinementItem.action == #selector(toggleTranscriptRefinementClicked)
    }
    var isRetryTranscriptionMenuItemVisible: Bool { !retryTranscriptionItem.isHidden }
    var isOpenLastRecordingEnabled: Bool { openLastRecordingItem.isEnabled }
    var isPauseResumeVisible: Bool { !pauseResumeItem.isHidden }
    var pauseResumeTitle: String { pauseResumeItem.title }
    var isPauseResumeEnabled: Bool { pauseResumeItem.isEnabled }
    var selectedScreenSource: ScreenCaptureSourcePreference? {
        let items: [(ScreenCaptureSourcePreference, NSMenuItem)] = [
            (.mainDisplay, mainDisplaySourceItem),
            (.systemPicker, systemPickerSourceItem),
            (.region, regionSourceItem),
        ]
        return items.first { $0.1.state == .on }?.0
    }

    var onToggle: (() -> Void)?
    var onStartAudioOnly: (() -> Void)?
    var onPauseResume: (() -> Void)?
    var onSelectScreenSource: ((ScreenCaptureSourcePreference) -> Void)?
    var onToggleCapturePrivacy: ((CapturePrivacyFeature) -> Void)?
    var onToggleRecordingName: (() -> Void)?
    var onEditRecordingNameTemplate: (() -> Void)?
    var onOpenLastVideoInGifski: (() -> Void)?
    var onSelectTranscriptionEngine: ((TranscriptionEngineOption) -> Void)?
    var onToggleTranscriptRefinement: (() -> Void)?
    var onSetUpParakeetModel: (() -> Void)?
    var onRetryTranscription: (() -> Void)?
    var onOpenFolder: (() -> Void)?
    var onOpenLastRecording: (() -> Void)?
    var onChooseExportFolder: (() -> Void)?
    var onCheckForUpdates: (() -> Void)?
    var onToggleLaunchAtLogin: (() -> Void)?
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

        pauseResumeItem = NSMenuItem(
            title: "Pause screen recording",
            action: #selector(pauseResumeClicked),
            keyEquivalent: ""
        )
        pauseResumeItem.isHidden = true
        pauseResumeItem.isEnabled = false
        menu.addItem(pauseResumeItem)

        audioOnlyItem = NSMenuItem(
            title: "Start audio-only recording",
            action: #selector(audioOnlyClicked),
            keyEquivalent: ""
        )
        menu.addItem(audioOnlyItem)

        screenSourceItem = NSMenuItem(
            title: Self.screenSourceMenuTitle,
            action: nil,
            keyEquivalent: ""
        )
        let screenSourceMenu = NSMenu(title: Self.screenSourceMenuTitle)
        screenSourceMenu.autoenablesItems = false
        mainDisplaySourceItem = Self.screenSourceMenuItem(for: .mainDisplay)
        systemPickerSourceItem = Self.screenSourceMenuItem(for: .systemPicker)
        regionSourceItem = Self.screenSourceMenuItem(for: .region)
        screenSourceMenu.addItem(mainDisplaySourceItem)
        screenSourceMenu.addItem(systemPickerSourceItem)
        screenSourceMenu.addItem(regionSourceItem)
        screenSourceItem.submenu = screenSourceMenu
        menu.addItem(screenSourceItem)

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
            title: Self.transcriptionModelMenuTitle,
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
        transcriptionMenu.addItem(.separator())
        transcriptRefinementItem = NSMenuItem(
            title: Self.transcriptRefinementMenuTitle,
            action: #selector(toggleTranscriptRefinementClicked),
            keyEquivalent: ""
        )
        transcriptionMenu.addItem(transcriptRefinementItem)
        transcriptionMenu.addItem(.separator())
        parakeetModelSetupItem = NSMenuItem(
            title: "Set Up Parakeet Model…",
            action: #selector(setUpParakeetModelClicked),
            keyEquivalent: ""
        )
        transcriptionMenu.addItem(parakeetModelSetupItem)
        transcriptionMenu.addItem(.separator())
        retryTranscriptionItem = NSMenuItem(
            title: "Retry Failed Transcription",
            action: #selector(retryTranscriptionClicked),
            keyEquivalent: ""
        )
        retryTranscriptionItem.isHidden = true
        retryTranscriptionItem.isEnabled = false
        transcriptionMenu.addItem(retryTranscriptionItem)
        transcriptionEngineItem.submenu = transcriptionMenu
        menu.addItem(transcriptionEngineItem)

        let openFolder = NSMenuItem(
            title: Self.openTempSessionMenuTitle,
            action: #selector(openFolderClicked),
            keyEquivalent: "o"
        )
        menu.addItem(openFolder)

        openLastRecordingItem = NSMenuItem(
            title: Self.openLastRecordingMenuTitle,
            action: #selector(openLastRecordingClicked),
            keyEquivalent: ""
        )
        openLastRecordingItem.isEnabled = false
        menu.addItem(openLastRecordingItem)

        exportFolderItem = NSMenuItem(
            title: Self.exportFolderMenuTitle,
            action: #selector(chooseExportFolderClicked),
            keyEquivalent: ""
        )
        menu.addItem(exportFolderItem)

        menu.addItem(.separator())

        checkForUpdatesItem = NSMenuItem(
            title: Self.checkForUpdatesMenuTitle,
            action: #selector(checkForUpdatesClicked),
            keyEquivalent: ""
        )
        menu.addItem(checkForUpdatesItem)

        launchAtLoginItem = NSMenuItem(
            title: Self.launchAtLoginMenuTitle,
            action: #selector(toggleLaunchAtLoginClicked),
            keyEquivalent: ""
        )
        menu.addItem(launchAtLoginItem)

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "Quit Record",
            action: #selector(quitClicked),
            keyEquivalent: "q"
        )
        menu.addItem(quit)

        for item in [
            toggleItem,
            pauseResumeItem,
            audioOnlyItem,
            mainDisplaySourceItem,
            systemPickerSourceItem,
            regionSourceItem,
            hideNotificationsItem,
            hideMenuBarItem,
            hideDesktopItemsItem,
            recordingNameItem,
            recordingNameTemplateItem,
            gifskiItem,
            parakeetEngineItem,
            macWhisperEngineItem,
            transcriptRefinementItem,
            parakeetModelSetupItem,
            retryTranscriptionItem,
            openFolder,
            openLastRecordingItem,
            exportFolderItem,
            checkForUpdatesItem,
            launchAtLoginItem,
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

    /// Reflect recording state in the icon and menu item titles. The menu bar
    /// shows a pulsing white Record ring while recording; the elapsed counter
    /// lives in the menu's state label. Call once a second while recording.
    func update(recording: Bool, elapsed: String?, mode: RecordingMode = .screen) {
        apply(
            recording
                ? .recording(
                    mode: mode,
                    elapsed: elapsed ?? "0:00",
                    healthNote: captureHealthNote
                )
                : .idle
        )
    }

    func updateRequestingPermissions(for mode: RecordingMode) {
        apply(.requestingPermissions(for: mode))
    }

    func updatePreparingScreenRecording() {
        apply(.preparingScreenRecording)
    }

    func updateStoppingScreenRecording(
        captureStarted: Bool,
        indicatorActive: Bool
    ) {
        apply(
            .stoppingScreenRecording(
                captureStarted: captureStarted,
                indicatorActive: indicatorActive
            )
        )
    }

    func updateSavingRecording() {
        apply(.savingRecording)
    }

    func updatePausedScreenRecording(elapsed: String) {
        apply(.pausedScreenRecording(elapsed: elapsed))
    }

    func updateRotatingScreenRecording(resuming: Bool) {
        apply(.rotatingScreenRecording(resuming: resuming))
    }

    func updateCaptureHealth(_ event: CaptureHealthEvent) {
        switch event.code {
        case .routeRecovered:
            captureHealthNote = nil
        case .routeChanged:
            captureHealthNote = "reconnecting microphone…"
        case .routeRecoveryFailed:
            captureHealthNote = "microphone reconnecting…"
        case .voiceProcessingFallback:
            captureHealthNote = "using compatible microphone mode"
        case .digitalSilence:
            captureHealthNote = "using raw microphone"
        case .queuePressure:
            captureHealthNote = "capture under load"
        case .writeFailed:
            captureHealthNote = "track write failed"
        case .missingCallbacks:
            captureHealthNote = "track captured no data"
        }
    }

    func updateCapturePrivacy(_ configuration: CapturePrivacyConfiguration) {
        hideNotificationsItem.state = configuration.hideNotifications ? .on : .off
        hideMenuBarItem.state = configuration.hideMenuBar ? .on : .off
        hideDesktopItemsItem.state = configuration.hideDesktopItems ? .on : .off
    }

    func updateScreenCaptureSource(_ source: ScreenCaptureSourcePreference) {
        mainDisplaySourceItem.state = source == .mainDisplay ? .on : .off
        systemPickerSourceItem.state = source == .systemPicker ? .on : .off
        regionSourceItem.state = source == .region ? .on : .off
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
    func updateTranscription(_ text: String?, retryAvailable: Bool = false) {
        transcriptionLabel.title = text ?? ""
        transcriptionLabel.isHidden = text == nil
        retryTranscriptionItem.isHidden = !retryAvailable
        retryTranscriptionItem.isEnabled = retryAvailable
    }

    func updateTranscriptionEngine(
        _ engine: TranscriptionEngineOption,
        macWhisperAvailable: Bool,
        parakeetModelAvailable: Bool
    ) {
        parakeetEngineItem.state = engine == .parakeet ? .on : .off
        macWhisperEngineItem.state = engine == .macwhisper ? .on : .off
        macWhisperEngineItem.isHidden = !macWhisperAvailable
        macWhisperEngineItem.isEnabled = macWhisperAvailable
        macWhisperEngineItem.title = "MacWhisper (Small)"
        macWhisperEngineItem.toolTip = "Uses the installed local MacWhisper Small model"
        parakeetModelSetupItem.isHidden = parakeetModelAvailable
        parakeetModelSetupItem.toolTip =
            "Download from FluidInference and import a verified local Parakeet model"
    }

    func updateTranscriptRefinement(enabled: Bool, available: Bool, detail: String) {
        transcriptRefinementItem.state = enabled ? .on : .off
        transcriptRefinementItem.isEnabled = available
        transcriptRefinementItem.toolTip = detail
    }

    /// Show the default or approved destination for finished exports. An
    /// ellipsis communicates that selecting the item opens a folder picker.
    func updateExportDirectory(_ url: URL) {
        exportFolderItem.title = Self.exportFolderMenuTitle
        exportFolderItem.toolTip = url.path
    }

    func updateLastRecording(available: Bool) {
        openLastRecordingItem.title = Self.openLastRecordingMenuTitle
        openLastRecordingItem.isEnabled = available
        openLastRecordingItem.toolTip =
            available ? "Reveal the most recently finished recording in Finder" : nil
    }

    func updateLaunchAtLogin(_ state: LaunchAtLoginState) {
        launchAtLoginItem.title = Self.launchAtLoginMenuTitle
        launchAtLoginItem.isEnabled = state != .unavailable
        launchAtLoginItem.state =
            switch state {
            case .disabled, .unavailable: .off
            case .enabled: .on
            case .requiresApproval: .mixed
            }
        launchAtLoginItem.toolTip =
            switch state {
            case .disabled: "Open Record automatically after you sign in"
            case .enabled: "Record will open automatically after you sign in"
            case .requiresApproval: "Click to approve Record in Login Items"
            case .unavailable: "Open at Login is unavailable for this copy of Record"
            }
    }

    // NewKap's MIT-licensed 2x menu-bar ring is embedded so the signed app has
    // no mutable external status-image dependency. Provenance lives in
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

    /// Template status-item images deliberately adapt between black and white.
    /// Recording state must remain conspicuous on every menu-bar appearance,
    /// so render the same NewKap ring as an explicit white, non-template image.
    static func recordingMenuBarImage() -> NSImage? {
        guard let source = menuBarImage() else { return nil }
        let image = NSImage(size: source.size, flipped: false) { rect in
            source.draw(in: rect)
            NSColor.white.setFill()
            rect.fill(using: .sourceIn)
            return true
        }
        image.isTemplate = false
        return image
    }

    static func recordingPulseAnimation() -> CABasicAnimation {
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 1.0
        animation.toValue = 0.35
        animation.duration = 0.65
        animation.autoreverses = true
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        return animation
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

    private static func screenSourceMenuItem(
        for source: ScreenCaptureSourcePreference
    ) -> NSMenuItem {
        let item = NSMenuItem(
            title: source.displayName,
            action: #selector(screenSourceClicked),
            keyEquivalent: ""
        )
        item.representedObject = source.rawValue
        return item
    }

    private func setCapturePrivacyItemsEnabled(_ enabled: Bool) {
        hideNotificationsItem.isEnabled = enabled
        hideMenuBarItem.isEnabled = enabled
        hideDesktopItemsItem.isEnabled = enabled
    }

    private func apply(_ presentation: RecordingMenuPresentation) {
        if presentation.clearsCaptureHealth {
            captureHealthNote = nil
        }
        stateLabel.title = presentation.stateTitle
        toggleItem.title = presentation.toggleTitle
        toggleItem.isEnabled = presentation.toggleEnabled
        pauseResumeItem.title = presentation.pauseResumeTitle
        pauseResumeItem.isHidden = !presentation.pauseResumeVisible
        pauseResumeItem.isEnabled = presentation.pauseResumeEnabled
        audioOnlyItem.isEnabled = presentation.audioOnlyEnabled
        screenSourceItem.isEnabled = presentation.screenSourceEnabled
        exportFolderItem.isEnabled = presentation.exportFolderEnabled
        setCapturePrivacyItemsEnabled(presentation.capturePrivacyEnabled)
        setRecordingIndicatorActive(presentation.recordingIndicatorActive)
    }

    private func setRecordingIndicatorActive(_ active: Bool) {
        guard recordingIndicatorIsActive != active else { return }
        recordingIndicatorIsActive = active
        guard let button = statusItem.button else { return }

        button.layer?.removeAnimation(forKey: Self.recordingPulseAnimationKey)
        button.alphaValue = 1
        button.contentTintColor = nil
        button.image = active ? Self.recordingMenuBarImage() : Self.menuBarImage()

        guard active, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            return
        }
        button.wantsLayer = true
        button.layer?.add(
            Self.recordingPulseAnimation(),
            forKey: Self.recordingPulseAnimationKey
        )
    }

    @objc private func toggleClicked() { onToggle?() }
    @objc private func pauseResumeClicked() { onPauseResume?() }
    @objc private func audioOnlyClicked() { onStartAudioOnly?() }
    @objc private func screenSourceClicked(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
            let source = ScreenCaptureSourcePreference(rawValue: rawValue)
        else { return }
        onSelectScreenSource?(source)
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
    @objc private func setUpParakeetModelClicked() { onSetUpParakeetModel?() }
    @objc private func toggleTranscriptRefinementClicked() {
        onToggleTranscriptRefinement?()
    }
    @objc private func retryTranscriptionClicked() { onRetryTranscription?() }
    @objc private func openFolderClicked() { onOpenFolder?() }
    @objc private func openLastRecordingClicked() { onOpenLastRecording?() }
    @objc private func chooseExportFolderClicked() { onChooseExportFolder?() }
    @objc private func checkForUpdatesClicked() { onCheckForUpdates?() }
    @objc private func toggleLaunchAtLoginClicked() { onToggleLaunchAtLogin?() }
    @objc private func quitClicked() { onQuit?() }
}
