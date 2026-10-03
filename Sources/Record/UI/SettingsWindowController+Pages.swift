import AppKit
import RecordCore

@MainActor
extension SettingsWindowController {
    func buildUI() {
        guard let content = window?.contentView else { return }
        let navigation = NSVisualEffectView()
        navigation.material = .sidebar
        navigation.blendingMode = .behindWindow
        let title = SettingsLayout.heading("Record", size: 19)
        let hint = SettingsLayout.note("Recording & preferences")
        sidebar.addTableColumn(NSTableColumn(identifier: .init("section")))
        sidebar.headerView = nil
        sidebar.style = .sourceList
        sidebar.rowHeight = 38
        sidebar.allowsEmptySelection = false
        sidebar.dataSource = self
        sidebar.delegate = self
        sidebar.setAccessibilityLabel("Record sections")
        let list = NSScrollView()
        list.drawsBackground = false
        list.documentView = sidebar
        list.hasVerticalScroller = true
        for view in [title, hint, list] {
            view.translatesAutoresizingMaskIntoConstraints = false
            navigation.addSubview(view)
        }
        let divider = NSBox()
        divider.boxType = .separator
        for view in [navigation, divider, pageContainer] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            navigation.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            navigation.topAnchor.constraint(equalTo: content.topAnchor),
            navigation.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            navigation.widthAnchor.constraint(equalToConstant: 190),
            title.leadingAnchor.constraint(equalTo: navigation.leadingAnchor, constant: 20),
            title.topAnchor.constraint(equalTo: navigation.topAnchor, constant: 24),
            hint.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            hint.trailingAnchor.constraint(equalTo: navigation.trailingAnchor, constant: -12),
            hint.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 5),
            list.topAnchor.constraint(equalTo: hint.bottomAnchor, constant: 20),
            list.leadingAnchor.constraint(equalTo: navigation.leadingAnchor, constant: 8),
            list.trailingAnchor.constraint(equalTo: navigation.trailingAnchor, constant: -8),
            list.bottomAnchor.constraint(equalTo: navigation.bottomAnchor, constant: -12),
            divider.leadingAnchor.constraint(equalTo: navigation.trailingAnchor),
            divider.widthAnchor.constraint(equalToConstant: 1),
            divider.topAnchor.constraint(equalTo: content.topAnchor),
            divider.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            pageContainer.leadingAnchor.constraint(equalTo: divider.trailingAnchor),
            pageContainer.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            pageContainer.topAnchor.constraint(equalTo: content.topAnchor),
            pageContainer.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        pageViews = [
            .recording: buildRecordingPage(), .sessions: sessions.view,
            .transcription: buildTranscriptionPage(), .screenshots: buildScreenshotsPage(),
            .shortcuts: buildShortcutsPage(), .general: buildGeneralPage(),
        ]
        for (section, view) in pageViews {
            view.identifier = .init("settings.\(section.title.lowercased())")
            view.translatesAutoresizingMaskIntoConstraints = false
            pageContainer.addSubview(view)
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: pageContainer.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: pageContainer.trailingAnchor),
                view.topAnchor.constraint(equalTo: pageContainer.topAnchor),
                view.bottomAnchor.constraint(equalTo: pageContainer.bottomAnchor),
            ])
        }
        window?.initialFirstResponder = sidebar
        window?.setFrameAutosaveName("RecordSettingsSidebar")
        window?.center()
    }

    func buildRecordingPage() -> NSView {
        SettingsLayout.page(
            title: "Recording",
            description: "Choose what to capture, check your input, and start recording here."
        ) { stack in
            recordingMode.selectedSegment = 0
            recordingMode.target = self
            recordingMode.action = #selector(recordingModeChanged)
            stack.addArrangedSubview(SettingsLayout.row("Mode", recordingMode))
            screenSourcePopup.addItems(
                withTitles: ScreenCaptureSourcePreference.allCases.map(\.displayName))
            screenSourcePopup.target = self
            screenSourcePopup.action = #selector(screenSourceChanged)
            stack.addArrangedSubview(SettingsLayout.row("Screen source", screenSourcePopup))
            sourcePopup.addItems(withTitles: RecordingAudioSource.allCases.map(\.title))
            sourcePopup.target = self
            sourcePopup.action = #selector(audioSourceChanged)
            stack.addArrangedSubview(SettingsLayout.row("Audio sources", sourcePopup))
            microphonePopup.target = self
            microphonePopup.action = #selector(microphoneChanged)
            microphonePopup.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            inputTestButton.target = self
            inputTestButton.action = #selector(testInput)
            stack.addArrangedSubview(
                SettingsLayout.row("Microphone", microphonePopup, inputTestButton))
            inputTestButton.setAccessibilityLabel("Test microphone input")
            for (label, level) in [
                ("Microphone activity", microphoneLevel), ("System audio activity", systemLevel),
            ] {
                level.minValue = 0
                level.maxValue = 1
                level.levelIndicatorStyle = .continuousCapacity
                level.widthAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true
                stack.addArrangedSubview(SettingsLayout.row(label, level))
            }
            audioStatus.textColor = .secondaryLabelColor
            stack.addArrangedSubview(audioStatus)
            stack.addArrangedSubview(
                SettingsLayout.note(
                    "Test Input listens for 10 seconds without saving. Audio sources stay in separate files."
                ))
            stack.addArrangedSubview(
                SettingsLayout.note(
                    "In audio-only mode, a specific microphone uses raw input. System Default retains voice processing."
                ))
            panelCheckbox.target = self
            panelCheckbox.action = #selector(panelChanged)
            stack.addArrangedSubview(panelCheckbox)
            stack.addArrangedSubview(SettingsLayout.heading("Before you start"))
            stack.addArrangedSubview(readinessLabel)
            checkPermissionsButton.target = self
            checkPermissionsButton.action = #selector(checkPermissions)
            startRecordingButton.target = self
            startRecordingButton.action = #selector(startRecording)
            stack.addArrangedSubview(
                NSStackView(views: [startRecordingButton, checkPermissionsButton]))
            captureLockNote.textColor = .secondaryLabelColor
            captureLockNote.isHidden = true
            stack.addArrangedSubview(captureLockNote)
            refreshAudioDevices()
        }
    }

    func buildGeneralPage() -> NSView {
        SettingsLayout.page(
            title: "General",
            description:
                "Choose where files go, how recordings are named, and what stays out of captures."
        ) { stack in
            stack.addArrangedSubview(SettingsLayout.heading("Save location"))
            chooseDestinationButton.target = self
            chooseDestinationButton.action = #selector(chooseExportFolder)
            destinationLabel.lineBreakMode = .byTruncatingMiddle
            destinationLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            stack.addArrangedSubview(
                SettingsLayout.row("Save to", destinationLabel, chooseDestinationButton))
            chooseDestinationButton.setAccessibilityLabel("Change save folder")
            stack.addArrangedSubview(
                SettingsLayout.note(
                    "Screenshots and finished recordings share this folder. Sessions shows this folder and private recovery storage."
                ))
            stack.addArrangedSubview(SettingsLayout.heading("Recording names"))
            renameRecordingCheckbox.target = self
            renameRecordingCheckbox.action = #selector(toggleRecordingName)
            stack.addArrangedSubview(renameRecordingCheckbox)
            recordingTemplateField.delegate = self
            recordingTemplateField.placeholderString = RecordingNameTemplate.defaultValue.rawValue
            recordingTemplateField.setContentHuggingPriority(.defaultLow, for: .horizontal)
            stack.addArrangedSubview(SettingsLayout.row("Name template", recordingTemplateField))
            stack.addArrangedSubview(recordingNamePreview)
            stack.addArrangedSubview(
                SettingsLayout.note(
                    "Tokens: {date}, {time}, {color}, {adjective}, {animal}, {country}, {name}, {starWars}, {clipboard}. The example uses placeholder clipboard text; actual clipboard content is read only for recording names that request it."
                ))
            stack.addArrangedSubview(SettingsLayout.heading("Capture privacy"))
            configurePrivacyCheckbox(
                hideNotificationsCheckbox, feature: .notifications,
                toolTip: "Applies to captures only. Notification sounds may still be recorded.")
            configurePrivacyCheckbox(
                hideMenuBarCheckbox, feature: .menuBar,
                toolTip: "Applies to captures only. Your macOS menu bar remains unchanged.")
            configurePrivacyCheckbox(
                hideDesktopItemsCheckbox, feature: .desktopItems,
                toolTip: "Applies to captures only. Existing Finder windows remain visible.")
            for checkbox in [
                hideNotificationsCheckbox, hideMenuBarCheckbox, hideDesktopItemsCheckbox,
            ] { stack.addArrangedSubview(checkbox) }
            stack.addArrangedSubview(
                SettingsLayout.note(
                    "These exclusions apply to screenshots and screen recordings. Notification sounds require Focus to silence."
                ))
            stack.addArrangedSubview(SettingsLayout.heading("Startup & support"))
            launchAtLoginCheckbox.target = self
            launchAtLoginCheckbox.action = #selector(toggleLaunchAtLogin)
            stack.addArrangedSubview(launchAtLoginCheckbox)
            stack.addArrangedSubview(
                NSButton(
                    title: MenuBarController.diagnosticsMenuTitle, target: self,
                    action: #selector(showDiagnostics)))
        }
    }

    func buildScreenshotsPage() -> NSView {
        SettingsLayout.page(
            title: "Screenshots",
            description:
                "Screenshots save to your chosen folder. A lossless PNG also goes to the clipboard."
        ) { stack in
            formatPopup.addItems(withTitles: ScreenshotImageFormat.allCases.map(\.displayName))
            formatPopup.target = self
            formatPopup.action = #selector(formatChanged)
            stack.addArrangedSubview(SettingsLayout.row("File format", formatPopup))
            qualitySlider.numberOfTickMarks = 11
            qualitySlider.target = self
            qualitySlider.action = #selector(qualityChanged)
            qualitySlider.widthAnchor.constraint(equalToConstant: 220).isActive = true
            stack.addArrangedSubview(
                SettingsLayout.row("JPEG quality", qualitySlider, qualityLabel))
            stack.addArrangedSubview(
                SettingsLayout.note("JPEG quality affects JPEG files only. PNG is always lossless.")
            )
            soundCheckbox.target = self
            soundCheckbox.action = #selector(soundChanged)
            stack.addArrangedSubview(soundCheckbox)
            stack.addArrangedSubview(
                SettingsLayout.note(
                    "Set capture shortcuts in Shortcuts. Change the shared save folder in General.")
            )
        }
    }

    func buildTranscriptionPage() -> NSView {
        SettingsLayout.page(
            title: "Transcription",
            description:
                "Create transcripts after recording. Model setup is optional; recording works without it."
        ) { stack in
            transcriptionPopup.addItems(withTitles: ["Parakeet (Default)", "MacWhisper (Small)"])
            transcriptionPopup.itemArray[0].representedObject =
                TranscriptionEngineOption.parakeet.rawValue
            transcriptionPopup.itemArray[1].representedObject =
                TranscriptionEngineOption.macwhisper.rawValue
            transcriptionPopup.target = self
            transcriptionPopup.action = #selector(transcriptionEngineChanged)
            stack.addArrangedSubview(SettingsLayout.row("Engine", transcriptionPopup))
            stack.addArrangedSubview(transcriptionAvailability)
            parakeetSetupButton.target = self
            parakeetSetupButton.action = #selector(setUpParakeetModel)
            stack.addArrangedSubview(
                SettingsLayout.row("Parakeet model", parakeetStatusLabel, parakeetSetupButton))
            parakeetSetupButton.setAccessibilityLabel("Set up the local Parakeet model")
            stack.addArrangedSubview(SettingsLayout.heading("Transcript cleanup"))
            transcriptRefinementCheckbox.target = self
            transcriptRefinementCheckbox.action = #selector(toggleTranscriptRefinement)
            stack.addArrangedSubview(transcriptRefinementCheckbox)
            refinementDetail.textColor = .secondaryLabelColor
            stack.addArrangedSubview(refinementDetail)
            stack.addArrangedSubview(
                SettingsLayout.note(
                    "Original recognition is retained. Open Sessions to compare clean and raw transcripts, retry unfinished tracks, or transcribe later."
                ))
        }
    }

    func buildShortcutsPage() -> NSView {
        SettingsLayout.page(
            title: "Shortcuts",
            description:
                "Click a shortcut, then press a key combination. Delete turns it off; Escape cancels. Shortcuts work across apps."
        ) { stack in
            stack.addArrangedSubview(SettingsLayout.heading("Recording"))
            for action in RecordingShortcutAction.allCases {
                let button = ShortcutRecorderButton()
                button.update(shortcut: recordingShortcuts[action])
                button.onRecord = { [weak self, weak button] shortcut in
                    guard let self else { return }
                    do {
                        try self.recordingShortcuts.set(
                            shortcut, for: action, screenshots: self.screenshotPreferences.shortcuts
                        )
                        button?.update(shortcut: shortcut)
                        self.recordingShortcutMessage.stringValue = ""
                        self.onRecordingShortcutsChanged?()
                    } catch {
                        self.recordingShortcutMessage.stringValue =
                            "That shortcut is already assigned to another Record action."
                    }
                }
                button.onInvalid = { [weak self] in self?.recordingShortcutMessage.stringValue = $0
                }
                recordingShortcutButtons[action] = button
                stack.addArrangedSubview(SettingsLayout.row(action.title, button))
            }
            recordingShortcutMessage.textColor = .systemOrange
            stack.addArrangedSubview(recordingShortcutMessage)
            stack.addArrangedSubview(SettingsLayout.heading("Screenshots"))
            for kind in ScreenshotCaptureKind.allCases {
                let button = ShortcutRecorderButton(kind: kind)
                button.onRecord = { [weak self] in self?.storeShortcut($0, for: kind) }
                button.onInvalid = { [weak self] in self?.screenshotMessageLabel.stringValue = $0 }
                shortcutButtons[kind] = button
                stack.addArrangedSubview(SettingsLayout.row(kind.displayName, button))
            }
            screenshotMessageLabel.textColor = .systemOrange
            stack.addArrangedSubview(screenshotMessageLabel)
            stack.addArrangedSubview(
                NSStackView(views: [
                    NSButton(
                        title: "Restore Screenshot Defaults", target: self,
                        action: #selector(restoreScreenshotDefaults)),
                    NSButton(
                        title: "macOS Keyboard Shortcuts…", target: self,
                        action: #selector(openSystemShortcuts)),
                ]))
        }
    }

    @objc func showDiagnostics() { onShowDiagnostics?() }
}
