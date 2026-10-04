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

/// One native settings surface for shared capture policy, screenshots, and
/// finished recordings. AppController remains the policy owner; this object
/// only renders current state and translates controls into narrow callbacks.
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate, NSTableViewDataSource,
    NSTableViewDelegate, NSTextFieldDelegate
{
    enum Section: Int, CaseIterable {
        case general, recording, sessions, transcription, screenshots, shortcuts
        var title: String {
            switch self {
            case .recording: L10n.text("Recording")
            case .sessions: L10n.text("Sessions")
            case .transcription: L10n.text("Transcription")
            case .screenshots: L10n.text("Screenshots")
            case .shortcuts: L10n.text("Shortcuts")
            case .general: L10n.text("General")
            }
        }
        var symbol: String {
            switch self {
            case .recording: "record.circle"
            case .sessions: "clock"
            case .transcription: "text.bubble"
            case .screenshots: "camera"
            case .shortcuts: "keyboard"
            case .general: "gearshape"
            }
        }
    }

    let screenshotPreferences: ScreenshotPreferences
    let sidebar = NSTableView()
    let sessions: RecentSessionsViewController
    private(set) var selectedSection: Section = .recording
    let pageContainer = NSView()
    var pageViews: [Section: NSView] = [:]

    let destinationLabel = NSTextField(labelWithString: "")
    let chooseDestinationButton = NSButton(
        title: L10n.text("Change…"), target: nil, action: nil)
    let hideNotificationsCheckbox = NSButton(
        checkboxWithTitle: L10n.text("Hide notifications from capture"), target: nil, action: nil)
    let hideMenuBarCheckbox = NSButton(
        checkboxWithTitle: L10n.text("Hide menu bar, including the clock"), target: nil, action: nil
    )
    let hideDesktopItemsCheckbox = NSButton(
        checkboxWithTitle: L10n.text("Hide Desktop items from capture"), target: nil, action: nil)
    let launchAtLoginCheckbox = NSButton(
        checkboxWithTitle: L10n.text("Open Record at Login"), target: nil, action: nil)

    let formatPopup = NSPopUpButton()
    let qualitySlider = NSSlider(
        value: 0.95,
        minValue: 0.5,
        maxValue: 1,
        target: nil,
        action: nil
    )
    let qualityLabel = NSTextField(labelWithString: "95%")
    let soundCheckbox = NSButton(
        checkboxWithTitle: L10n.text("Play shutter sound"), target: nil, action: nil)
    let screenshotMessageLabel = NSTextField(wrappingLabelWithString: "")
    var shortcutButtons: [ScreenshotCaptureKind: ShortcutRecorderButton] = [:]

    let renameRecordingCheckbox = NSButton(
        checkboxWithTitle: L10n.text("Rename finished recordings"), target: nil, action: nil)
    let recordingTemplateField = NSTextField(string: "")
    let recordingNamePreview = NSTextField(wrappingLabelWithString: "")
    let refinementDetail = NSTextField(wrappingLabelWithString: "")
    let transcriptionAvailability = NSTextField(wrappingLabelWithString: "")
    let recordingMode = NSSegmentedControl(
        labels: [L10n.text("Screen"), L10n.text("Audio only")], trackingMode: .selectOne,
        target: nil, action: nil)
    let screenSourcePopup = NSPopUpButton()
    let readinessLabel = NSTextField(wrappingLabelWithString: "")
    let checkPermissionsButton = NSButton(
        title: L10n.text("Check Permissions…"), target: nil, action: nil)
    let startRecordingButton = NSButton(
        title: L10n.text("Start Screen Recording"), target: nil, action: nil)
    let captureLockNote = NSTextField(wrappingLabelWithString: "")
    var interactionAvailability = SettingsInteractionAvailability.idle
    var onRefreshReadiness: ((RecordingMode) -> RecordingReadiness)?
    var onCheckPermissions: ((RecordingMode) -> Void)?
    var onStartRecording: ((RecordingMode) -> Void)?
    var onSelectScreenSource: ((ScreenCaptureSourcePreference) -> Void)?
    var onSectionChanged: ((Section) -> Void)?
    let transcriptionPopup = NSPopUpButton()
    let speechLanguagePopup = NSPopUpButton()
    let speechLanguageDetail = NSTextField(wrappingLabelWithString: "")
    let interfaceLanguagePopup = NSPopUpButton()
    let interfaceLanguageDetail = NSTextField(wrappingLabelWithString: "")
    let parakeetStatusLabel = NSTextField(labelWithString: "")
    let parakeetSetupButton = NSButton(
        title: L10n.text("Set Up Parakeet Model…"), target: nil, action: nil)
    let transcriptRefinementCheckbox = NSButton(
        checkboxWithTitle: L10n.text("Improve Transcript Readability"), target: nil, action: nil)

    let audioPreferences = RecordingAudioPreferences()
    let sourcePopup = NSPopUpButton()
    let microphonePopup = NSPopUpButton()
    let inputTestButton = NSButton(title: L10n.text("Test Input"), target: nil, action: nil)
    let audioStatus = NSTextField(wrappingLabelWithString: "")
    let microphoneLevel = NSLevelIndicator()
    let systemLevel = NSLevelIndicator()
    let panelCheckbox = NSButton(
        checkboxWithTitle: L10n.text("Show compact panel while recording"), target: nil, action: nil
    )
    let inputTest = AudioInputTest()
    var inputTestTask: Task<Void, Never>?
    var inputTestGeneration = UUID()
    var inputTestTimer: Timer?
    let recordingShortcuts = RecordingShortcuts()
    var recordingShortcutButtons: [RecordingShortcutAction: ShortcutRecorderButton] = [:]
    let recordingShortcutMessage = NSTextField(wrappingLabelWithString: "")
    var onRecordingShortcutsChanged: (() -> Void)?
    var onAudioPreferencesChanged: (() -> Void)?

    var onShowDiagnostics: (() -> Void)?
    var onChooseExportFolder: (() -> Void)?
    var onScreenshotPreferencesChanged: (() -> Void)?
    var onToggleCapturePrivacy: ((CapturePrivacyFeature) -> Void)?
    var onToggleLaunchAtLogin: (() -> Void)?
    var onToggleRecordingName: (() -> Void)?
    var onUpdateRecordingNameTemplate: ((String) -> Void)?
    var onSelectTranscriptionEngine: ((TranscriptionEngineOption) -> Void)?
    var onSelectSpeechLanguage: ((String) -> Void)?
    var onSetUpParakeetModel: (() -> Void)?
    var onToggleTranscriptRefinement: (() -> Void)?

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

    init(
        screenshotPreferences: ScreenshotPreferences,
        sessions: RecentSessionsViewController = RecentSessionsViewController()
    ) {
        self.sessions = sessions
        self.screenshotPreferences = screenshotPreferences
        let window = SettingsWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 700),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.text("Record Settings")
        window.contentMinSize = NSSize(width: 900, height: 620)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        buildUI()
        refreshScreenshotPreferences()
        select(section: .recording)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func show(exportDirectory: URL) {
        updateExportDirectory(exportDirectory)
        refreshScreenshotPreferences()
        refreshAudioDevices()
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        refreshReadiness()
        onSectionChanged?(selectedSection)
    }

    var isShowingSessions: Bool { window?.isVisible == true && selectedSection == .sessions }
    var selectedRecordingMode: RecordingMode {
        recordingMode.selectedSegment == 1 ? .audioOnly : .screen
    }

    func select(section: Section) {
        if selectedSection != section {
            window?.makeFirstResponder(sidebar)
            stopInputTest()
            if selectedSection == .sessions { sessions.endBrowsing() }
        }
        selectedSection = section
        sidebar.selectRowIndexes(IndexSet(integer: section.rawValue), byExtendingSelection: false)
        for (candidate, view) in pageViews { view.isHidden = candidate != section }
        if section == .recording { refreshReadiness() }
        if window?.isVisible == true { onSectionChanged?(section) }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { Section.allCases.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int)
        -> NSView?
    {
        let section = Section.allCases[row]
        return SettingsLayout.sidebarRow(section.title, symbol: section.symbol)
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let section = Section(rawValue: sidebar.selectedRow), section != selectedSection
        else { return }
        select(section: section)
    }

    func windowDidBecomeKey(_ notification: Notification) { refreshReadiness() }
    func refreshReadiness() {
        readinessLabel.stringValue =
            onRefreshReadiness?(selectedRecordingMode).checklist.joined(separator: "\n") ?? ""
    }
    func updateScreenSource(_ source: ScreenCaptureSourcePreference) {
        screenSourcePopup.selectItem(
            at: ScreenCaptureSourcePreference.allCases.firstIndex(of: source) ?? 0)
    }
    @objc func recordingModeChanged() {
        screenSourcePopup.isEnabled =
            selectedRecordingMode == .screen && interactionAvailability.capturePrivacyEnabled
        startRecordingButton.title =
            selectedRecordingMode == .screen
            ? L10n.text("Start Screen Recording") : L10n.text("Start Audio Recording")
        refreshReadiness()
    }
    @objc func screenSourceChanged() {
        onSelectScreenSource?(
            ScreenCaptureSourcePreference.allCases[screenSourcePopup.indexOfSelectedItem])
    }
    @objc func checkPermissions() { stopInputTest(); onCheckPermissions?(selectedRecordingMode) }
    @objc func startRecording() { stopInputTest(); onStartRecording?(selectedRecordingMode) }

    func updateExportDirectory(_ url: URL) {
        destinationLabel.stringValue = url.path
        destinationLabel.toolTip = url.path
        refreshReadiness()
    }

    func updateInteractionAvailability(_ availability: SettingsInteractionAvailability) {
        interactionAvailability = availability
        chooseDestinationButton.isEnabled = availability.destinationSelectionEnabled
        recordingMode.isEnabled = availability.capturePrivacyEnabled
        screenSourcePopup.isEnabled =
            availability.capturePrivacyEnabled && selectedRecordingMode == .screen
        startRecordingButton.isEnabled =
            availability.capturePrivacyEnabled && availability.destinationSelectionEnabled
        checkPermissionsButton.isEnabled = startRecordingButton.isEnabled
        captureLockNote.stringValue =
            startRecordingButton.isEnabled
            ? ""
            : L10n.text(
                "Recording controls are locked while capture is starting, running, or saving.")
        captureLockNote.isHidden = startRecordingButton.isEnabled
        sourcePopup.isEnabled = availability.capturePrivacyEnabled
        microphonePopup.isEnabled = availability.capturePrivacyEnabled
        inputTestButton.isEnabled = availability.capturePrivacyEnabled
        if !availability.capturePrivacyEnabled {
            stopInputTest()
        } else if inputTestTask == nil {
            microphoneLevel.doubleValue = 0
            systemLevel.doubleValue = 0
        }
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
            case .disabled: L10n.text("Open Record automatically after you sign in")
            case .enabled: L10n.text("Record will open automatically after you sign in")
            case .requiresApproval: L10n.text("Click to approve Record in Login Items")
            case .unavailable: L10n.text("Open at Login is unavailable for this copy of Record")
            }
    }

    func updateRecordingName(enabled: Bool, template: String) {
        renameRecordingCheckbox.state = enabled ? .on : .off
        if recordingTemplateField.currentEditor() == nil {
            recordingTemplateField.stringValue = template
        }
        recordingTemplateField.isEnabled = enabled
        updateNamePreview()
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
        transcriptionAvailability.stringValue =
            macWhisperAvailable
            ? L10n.text("All transcription runs locally on this Mac.")
            : L10n.text(
                "Transcription runs locally. Parakeet needs a one-time model setup. Install MacWhisper to make its engine available."
            )
        if let item = transcriptionPopup.itemArray.first(where: {
            $0.representedObject as? String == engine.rawValue
        }) {
            transcriptionPopup.select(item)
        }
        parakeetStatusLabel.stringValue =
            if parakeetModelAvailable {
                L10n.text("Installed")
            } else if parakeetSetupInProgress {
                L10n.text("Downloading and verifying…")
            } else {
                L10n.text("Setup required")
            }
        parakeetStatusLabel.textColor =
            parakeetModelAvailable ? .secondaryLabelColor : .systemOrange
        parakeetSetupButton.isHidden = parakeetModelAvailable
        parakeetSetupButton.isEnabled = !parakeetSetupInProgress
        parakeetSetupButton.title =
            parakeetSetupInProgress
            ? L10n.text("Downloading…") : L10n.text("Set Up Parakeet Model…")
    }

    func updateTranscriptRefinement(enabled: Bool, available: Bool, detail: String) {
        transcriptRefinementCheckbox.state = enabled ? .on : .off
        transcriptRefinementCheckbox.isEnabled = available
        transcriptRefinementCheckbox.toolTip = L10n.text(detail)
        refinementDetail.stringValue = L10n.text(detail)
    }

    func updateSpeechLanguage(engine: TranscriptionEngineOption, preferred: String) {
        speechLanguagePopup.removeAllItems()
        let options = [
            ("auto", L10n.text("Automatic")), ("en", L10n.text("English")),
            ("es", L10n.text("Spanish")),
        ]
        for (code, title) in options {
            speechLanguagePopup.addItem(withTitle: title)
            speechLanguagePopup.lastItem?.representedObject = code
        }
        if !options.contains(where: { $0.0 == preferred }) {
            speechLanguagePopup.addItem(
                withTitle: Locale(identifier: L10n.language.rawValue)
                    .localizedString(forLanguageCode: preferred) ?? preferred)
            speechLanguagePopup.lastItem?.representedObject = preferred
        }
        let effective = engine == .parakeet ? "auto" : preferred
        speechLanguagePopup.select(
            speechLanguagePopup.itemArray.first {
                $0.representedObject as? String == effective
            })
        speechLanguagePopup.isEnabled = engine == .macwhisper
        speechLanguageDetail.stringValue =
            engine == .parakeet
            ? L10n.text(
                "Parakeet detects language automatically. Your MacWhisper language choice is kept."
            )
            : L10n.text(
                "Applies to the next session processed. Interface language is set separately in General."
            )
    }

    @objc func speechLanguageChanged() {
        guard let language = speechLanguagePopup.selectedItem?.representedObject as? String else {
            return
        }
        onSelectSpeechLanguage?(language)
    }

    @objc func interfaceLanguageChanged() {
        guard let choice = interfaceLanguagePopup.selectedItem?.representedObject as? String else {
            return
        }
        UserDefaults.standard.set(choice, forKey: L10n.preferenceKey)
        if choice == InterfaceLanguage.system.rawValue {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([choice], forKey: "AppleLanguages")
        }
        interfaceLanguageDetail.stringValue = L10n.text(
            "Quit and reopen Record to apply the interface language. Speech language is unchanged.")
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
            L10n.format("Couldn’t register: %@. Another app or macOS is using the shortcut.", names)
    }

    func refreshAudioDevices() {
        microphonePopup.removeAllItems()
        microphonePopup.addItem(withTitle: L10n.text("System Default"))
        let devices = AudioInputDevices.available()
        for device in devices {
            microphonePopup.addItem(withTitle: device.name)
            microphonePopup.lastItem?.representedObject = device.uid
        }
        if let uid = audioPreferences.microphoneUID {
            if let item = microphonePopup.itemArray.first(where: {
                $0.representedObject as? String == uid
            }) {
                microphonePopup.select(item)
            } else {
                if inputTestTask != nil {
                    stopInputTest()
                    audioStatus.stringValue =
                        L10n.text("Selected microphone disconnected. Choose another input.")
                }
                microphonePopup.addItem(withTitle: L10n.text("Selected microphone unavailable"))
                microphonePopup.lastItem?.representedObject = uid
                microphonePopup.select(microphonePopup.lastItem)
            }
        }
        sourcePopup.selectItem(
            at: RecordingAudioSource.allCases.firstIndex(of: audioPreferences.source) ?? 0)
        panelCheckbox.state = audioPreferences.showsPanel ? .on : .off
    }

    func updateAudioLevels(
        _ levels: (microphone: Double, system: Double), configuration: CaptureAudioConfiguration
    ) {
        microphoneLevel.doubleValue = configuration.includeMicrophone ? levels.microphone : 0
        systemLevel.doubleValue = configuration.includeSystemAudio ? levels.system : 0
    }

    @objc func audioSourceChanged() {
        stopInputTest()
        audioPreferences.source = RecordingAudioSource.allCases[sourcePopup.indexOfSelectedItem]
        onAudioPreferencesChanged?()
        refreshReadiness()
    }
    @objc func microphoneChanged() {
        stopInputTest()
        audioPreferences.microphoneUID = microphonePopup.selectedItem?.representedObject as? String
        onAudioPreferencesChanged?()
        refreshReadiness()
    }
    @objc func panelChanged() {
        audioPreferences.showsPanel = panelCheckbox.state == .on
        onAudioPreferencesChanged?()
        refreshReadiness()
    }
    @objc func testInput() {
        if inputTestTask != nil { stopInputTest(); return }
        inputTestButton.title = L10n.text("Stop Test")
        let generation = UUID()
        inputTestGeneration = generation
        inputTestTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.inputTest.start(uid: self.audioPreferences.microphoneUID)
                self.audioStatus.stringValue =
                    L10n.text("Listening — speak to check the microphone. No audio is saved.")
                self.inputTestTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) {
                    [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        self.microphoneLevel.doubleValue = self.inputTest.activity.level()
                    }
                }
                try await Task.sleep(for: .seconds(10))
                guard self.inputTest.activity.hasReceivedSamples else {
                    self.audioStatus.stringValue =
                        L10n.text(
                            "No microphone audio received. Choose another input and test again.")
                    if self.inputTestGeneration == generation {
                        self.stopInputTest(preserveMessage: true)
                    }
                    return
                }
                self.audioStatus.stringValue = L10n.text("Input test finished.")
                UserDefaults.standard.set(
                    self.audioPreferences.microphoneUID ?? "default",
                    forKey: "recording.testedInput")
            } catch is CancellationError {} catch {
                self.audioStatus.stringValue =
                    L10n.text(
                        "Input unavailable. Check Microphone permission or choose another device.")
            }
            if self.inputTestGeneration == generation { self.stopInputTest(preserveMessage: true) }
        }
    }
    func stopInputTest(preserveMessage: Bool = false) {
        if inputTestTask != nil && !preserveMessage {
            audioStatus.stringValue = L10n.text("Input test stopped.")
        }
        inputTestGeneration = UUID()
        inputTestTask?.cancel()
        inputTestTask = nil
        inputTestTimer?.invalidate()
        inputTestTimer = nil
        inputTest.stop()
        inputTestButton.title = L10n.text("Test Input")
        microphoneLevel.doubleValue = 0
        refreshReadiness()
    }
    func windowWillClose(_ notification: Notification) {
        stopInputTest()
        sessions.endBrowsing()
        UserDefaults.standard.set(true, forKey: "recording.checklistDismissed")
    }

    func updateRecordingShortcutFailures(_ failures: [RecordingShortcutAction]) {
        recordingShortcutMessage.stringValue =
            failures.isEmpty
            ? ""
            : L10n.format(
                "Unavailable shortcuts: %@. Choose another combination.",
                failures.map(\.title).joined(separator: ", "))
    }

    func configurePrivacyCheckbox(
        _ checkbox: NSButton,
        feature: CapturePrivacyFeature,
        toolTip: String
    ) {
        checkbox.identifier = NSUserInterfaceItemIdentifier(feature.rawValue)
        checkbox.target = self
        checkbox.action = #selector(toggleCapturePrivacy)
        checkbox.toolTip = toolTip
    }

    func refreshScreenshotPreferences() {
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

    func storeShortcut(
        _ shortcut: ScreenshotShortcut?,
        for kind: ScreenshotCaptureKind
    ) {
        do {
            try RecordingShortcuts.check(
                shortcut,
                against: RecordingShortcutAction.allCases.compactMap { recordingShortcuts[$0] })
            try screenshotPreferences.setShortcut(shortcut, for: kind)
            screenshotMessageLabel.stringValue = ""
            refreshScreenshotPreferences()
            onScreenshotPreferencesChanged?()
        } catch ScreenshotCaptureContractError.duplicateShortcut {
            screenshotMessageLabel.stringValue =
                L10n.text("That shortcut is already assigned to another Record action.")
            NSSound.beep()
            refreshScreenshotPreferences()
        } catch {
            screenshotMessageLabel.stringValue = L10n.text("That shortcut can’t be saved.")
            NSSound.beep()
            refreshScreenshotPreferences()
        }
    }

    @objc func chooseExportFolder() { onChooseExportFolder?() }

    @objc func toggleCapturePrivacy(_ sender: NSButton) {
        guard let rawValue = sender.identifier?.rawValue,
            let feature = CapturePrivacyFeature(rawValue: rawValue)
        else { return }
        onToggleCapturePrivacy?(feature)
    }

    @objc func toggleLaunchAtLogin() { onToggleLaunchAtLogin?() }
    @objc func toggleRecordingName() { onToggleRecordingName?() }
    func controlTextDidChange(_ notification: Notification) {
        guard notification.object as? NSTextField === recordingTemplateField else { return }
        if updateNamePreview() {
            onUpdateRecordingNameTemplate?(recordingTemplateField.stringValue)
        }
    }
    @discardableResult
    func updateNamePreview() -> Bool {
        do {
            let template = try RecordingNameTemplate(validating: recordingTemplateField.stringValue)
            let preview = template.render(
                at: Date(), clipboard: L10n.text("Clipboard"), wordSeed: 0)
            recordingNamePreview.stringValue = L10n.text("Example: ") + preview
            recordingNamePreview.textColor = .secondaryLabelColor
            return true
        } catch {
            recordingNamePreview.stringValue =
                L10n.text(
                    "Use supported tokens and balanced braces. Your last valid template is still saved."
                )
            recordingNamePreview.textColor = .systemOrange
            return false
        }
    }

    @objc func transcriptionEngineChanged() {
        guard
            let rawValue = transcriptionPopup.selectedItem?.representedObject as? String,
            let engine = TranscriptionEngineOption(rawValue: rawValue)
        else { return }
        onSelectTranscriptionEngine?(engine)
    }

    @objc func setUpParakeetModel() { onSetUpParakeetModel?() }
    @objc func toggleTranscriptRefinement() { onToggleTranscriptRefinement?() }

    @objc func formatChanged() {
        screenshotPreferences.format = formatPopup.indexOfSelectedItem == 0 ? .png : .jpeg
        refreshScreenshotPreferences()
        onScreenshotPreferencesChanged?()
    }

    @objc func qualityChanged() {
        screenshotPreferences.jpegQuality = qualitySlider.doubleValue
        refreshScreenshotPreferences()
        onScreenshotPreferencesChanged?()
    }

    @objc func soundChanged() {
        screenshotPreferences.playShutterSound = soundCheckbox.state == .on
        onScreenshotPreferencesChanged?()
    }

    @objc func restoreScreenshotDefaults() {
        let recordings = RecordingShortcutAction.allCases.compactMap { recordingShortcuts[$0] }
        do {
            for kind in ScreenshotCaptureKind.allCases {
                try RecordingShortcuts.check(
                    ScreenshotShortcutSet.defaults[kind], against: recordings)
            }
        } catch {
            screenshotMessageLabel.stringValue =
                L10n.text(
                    "A default shortcut is assigned to recording. Change that recording shortcut first."
                )
            return
        }
        screenshotPreferences.restoreDefaultShortcuts()
        refreshScreenshotPreferences()
        onScreenshotPreferencesChanged?()
    }

    @objc func openSystemShortcuts() {
        guard
            let url = URL(
                string:
                    "x-apple.systempreferences:com.apple.Keyboard-Settings.extension?Shortcuts"
            )
        else { return }
        NSWorkspace.shared.open(url)
    }
}
