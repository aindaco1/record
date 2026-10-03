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
        let hint = SettingsLayout.note(L10n.text("Recording & preferences"))
        sidebar.addTableColumn(NSTableColumn(identifier: .init("section")))
        sidebar.headerView = nil
        sidebar.style = .sourceList
        sidebar.rowHeight = 38
        sidebar.allowsEmptySelection = false
        sidebar.dataSource = self
        sidebar.delegate = self
        sidebar.setAccessibilityLabel(L10n.text("Record sections"))
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
            view.identifier = .init("settings.\(String(describing: section))")
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
            title: L10n.text("Recording"),
            description: L10n.text(
                "Choose what to capture, check your input, and start recording here.")
        ) { stack in
            recordingMode.selectedSegment = 0
            recordingMode.target = self
            recordingMode.action = #selector(recordingModeChanged)
            stack.addArrangedSubview(SettingsLayout.row(L10n.text("Mode"), recordingMode))
            screenSourcePopup.addItems(
                withTitles: ScreenCaptureSourcePreference.allCases.map(\.displayName))
            screenSourcePopup.target = self
            screenSourcePopup.action = #selector(screenSourceChanged)
            stack.addArrangedSubview(
                SettingsLayout.row(L10n.text("Screen source"), screenSourcePopup))
            sourcePopup.addItems(withTitles: RecordingAudioSource.allCases.map(\.title))
            sourcePopup.target = self
            sourcePopup.action = #selector(audioSourceChanged)
            stack.addArrangedSubview(SettingsLayout.row(L10n.text("Audio sources"), sourcePopup))
            microphonePopup.target = self
            microphonePopup.action = #selector(microphoneChanged)
            microphonePopup.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            inputTestButton.target = self
            inputTestButton.action = #selector(testInput)
            stack.addArrangedSubview(
                SettingsLayout.row(L10n.text("Microphone"), microphonePopup, inputTestButton))
            inputTestButton.setAccessibilityLabel(L10n.text("Test microphone input"))
            for (label, level) in [
                (L10n.text("Microphone activity"), microphoneLevel),
                (L10n.text("System audio activity"), systemLevel),
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
                    L10n.text(
                        "Test Input listens for 10 seconds without saving. Audio sources stay in separate files."
                    )
                ))
            stack.addArrangedSubview(
                SettingsLayout.note(
                    L10n.text(
                        "In audio-only mode, a specific microphone uses raw input. System Default retains voice processing."
                    )
                ))
            panelCheckbox.target = self
            panelCheckbox.action = #selector(panelChanged)
            stack.addArrangedSubview(panelCheckbox)
            stack.addArrangedSubview(SettingsLayout.heading(L10n.text("Before you start")))
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
            title: L10n.text("General"),
            description:
                L10n.text(
                    "Choose where files go, how recordings are named, and what stays out of captures."
                )
        ) { stack in
            for (choice, title) in [
                (InterfaceLanguage.system, L10n.text("Follow macOS")),
                (.english, L10n.text("English")), (.spanish, "Español"),
            ] {
                interfaceLanguagePopup.addItem(withTitle: title)
                interfaceLanguagePopup.lastItem?.representedObject = choice.rawValue
            }
            let languageChoice =
                UserDefaults.standard.string(forKey: L10n.preferenceKey) ?? "system"
            interfaceLanguagePopup.select(
                interfaceLanguagePopup.itemArray.first {
                    $0.representedObject as? String == languageChoice
                })
            interfaceLanguagePopup.target = self
            interfaceLanguagePopup.action = #selector(interfaceLanguageChanged)
            stack.addArrangedSubview(
                SettingsLayout.row(L10n.text("Interface language"), interfaceLanguagePopup))
            stack.addArrangedSubview(interfaceLanguageDetail)
            stack.addArrangedSubview(SettingsLayout.heading(L10n.text("Save location")))
            chooseDestinationButton.target = self
            chooseDestinationButton.action = #selector(chooseExportFolder)
            destinationLabel.lineBreakMode = .byTruncatingMiddle
            destinationLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            stack.addArrangedSubview(
                SettingsLayout.row(L10n.text("Save to"), destinationLabel, chooseDestinationButton))
            chooseDestinationButton.setAccessibilityLabel(L10n.text("Change save folder"))
            stack.addArrangedSubview(
                SettingsLayout.note(
                    L10n.text(
                        "Screenshots and finished recordings share this folder. Sessions shows this folder and private recovery storage."
                    )
                ))
            stack.addArrangedSubview(SettingsLayout.heading(L10n.text("Recording names")))
            renameRecordingCheckbox.target = self
            renameRecordingCheckbox.action = #selector(toggleRecordingName)
            stack.addArrangedSubview(renameRecordingCheckbox)
            recordingTemplateField.delegate = self
            recordingTemplateField.placeholderString = RecordingNameTemplate.defaultValue.rawValue
            recordingTemplateField.setContentHuggingPriority(.defaultLow, for: .horizontal)
            stack.addArrangedSubview(
                SettingsLayout.row(L10n.text("Name template"), recordingTemplateField))
            stack.addArrangedSubview(recordingNamePreview)
            stack.addArrangedSubview(
                SettingsLayout.note(
                    L10n.text(
                        "Tokens: {date}, {time}, {color}, {adjective}, {animal}, {country}, {name}, {starWars}, {clipboard}. The example uses placeholder clipboard text; actual clipboard content is read only for recording names that request it."
                    )
                ))
            stack.addArrangedSubview(SettingsLayout.heading(L10n.text("Capture privacy")))
            configurePrivacyCheckbox(
                hideNotificationsCheckbox, feature: .notifications,
                toolTip: L10n.text(
                    "Applies to captures only. Notification sounds may still be recorded."))
            configurePrivacyCheckbox(
                hideMenuBarCheckbox, feature: .menuBar,
                toolTip: L10n.text(
                    "Applies to captures only. Your macOS menu bar remains unchanged."))
            configurePrivacyCheckbox(
                hideDesktopItemsCheckbox, feature: .desktopItems,
                toolTip: L10n.text(
                    "Applies to captures only. Existing Finder windows remain visible."))
            for checkbox in [
                hideNotificationsCheckbox, hideMenuBarCheckbox, hideDesktopItemsCheckbox,
            ] { stack.addArrangedSubview(checkbox) }
            stack.addArrangedSubview(
                SettingsLayout.note(
                    L10n.text(
                        "These exclusions apply to screenshots and screen recordings. Notification sounds require Focus to silence."
                    )
                ))
            stack.addArrangedSubview(SettingsLayout.heading(L10n.text("Startup & support")))
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
            title: L10n.text("Screenshots"),
            description:
                L10n.text(
                    "Screenshots save to your chosen folder. A lossless PNG also goes to the clipboard."
                )
        ) { stack in
            formatPopup.addItems(withTitles: ScreenshotImageFormat.allCases.map(\.displayName))
            formatPopup.target = self
            formatPopup.action = #selector(formatChanged)
            stack.addArrangedSubview(SettingsLayout.row(L10n.text("File format"), formatPopup))
            qualitySlider.numberOfTickMarks = 11
            qualitySlider.target = self
            qualitySlider.action = #selector(qualityChanged)
            qualitySlider.widthAnchor.constraint(equalToConstant: 220).isActive = true
            stack.addArrangedSubview(
                SettingsLayout.row(L10n.text("JPEG quality"), qualitySlider, qualityLabel))
            stack.addArrangedSubview(
                SettingsLayout.note(
                    L10n.text("JPEG quality affects JPEG files only. PNG is always lossless."))
            )
            soundCheckbox.target = self
            soundCheckbox.action = #selector(soundChanged)
            stack.addArrangedSubview(soundCheckbox)
            stack.addArrangedSubview(
                SettingsLayout.note(
                    L10n.text(
                        "Set capture shortcuts in Shortcuts. Change the shared save folder in General."
                    ))
            )
        }
    }

    func buildTranscriptionPage() -> NSView {
        SettingsLayout.page(
            title: L10n.text("Transcription"),
            description:
                L10n.text(
                    "Create transcripts after recording. Model setup is optional; recording works without it."
                )
        ) { stack in
            transcriptionPopup.addItems(withTitles: [
                L10n.text("Parakeet (Default)"), L10n.text("MacWhisper (Small)"),
            ])
            transcriptionPopup.itemArray[0].representedObject =
                TranscriptionEngineOption.parakeet.rawValue
            transcriptionPopup.itemArray[1].representedObject =
                TranscriptionEngineOption.macwhisper.rawValue
            transcriptionPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 240).isActive =
                true
            speechLanguagePopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive =
                true
            transcriptionPopup.target = self
            transcriptionPopup.action = #selector(transcriptionEngineChanged)
            stack.addArrangedSubview(SettingsLayout.row(L10n.text("Engine"), transcriptionPopup))
            speechLanguagePopup.target = self
            speechLanguagePopup.action = #selector(speechLanguageChanged)
            stack.addArrangedSubview(
                SettingsLayout.row(L10n.text("Speech language"), speechLanguagePopup))
            stack.addArrangedSubview(speechLanguageDetail)
            stack.addArrangedSubview(transcriptionAvailability)
            parakeetSetupButton.target = self
            parakeetSetupButton.action = #selector(setUpParakeetModel)
            stack.addArrangedSubview(
                SettingsLayout.row(
                    L10n.text("Parakeet model"), parakeetStatusLabel, parakeetSetupButton))
            parakeetSetupButton.setAccessibilityLabel(L10n.text("Set up the local Parakeet model"))
            stack.addArrangedSubview(SettingsLayout.heading(L10n.text("Vocabulary")))
            stack.addArrangedSubview(
                SettingsLayout.note(
                    L10n.text(
                        "Preferred spellings apply automatically to every new transcript. Case and spacing variants match automatically; separate other aliases with semicolons. For existing sessions, use Apply Vocabulary in Sessions."
                    )))
            stack.addArrangedSubview(VocabularySettingsView())
            stack.addArrangedSubview(SettingsLayout.heading(L10n.text("Transcript cleanup")))
            transcriptRefinementCheckbox.target = self
            transcriptRefinementCheckbox.action = #selector(toggleTranscriptRefinement)
            stack.addArrangedSubview(transcriptRefinementCheckbox)
            refinementDetail.textColor = .secondaryLabelColor
            stack.addArrangedSubview(refinementDetail)
            stack.addArrangedSubview(
                SettingsLayout.note(
                    L10n.text(
                        "Original recognition is retained. Open Sessions to compare clean and raw transcripts, retry unfinished tracks, or transcribe later."
                    )
                ))
        }
    }

    func buildShortcutsPage() -> NSView {
        SettingsLayout.page(
            title: L10n.text("Shortcuts"),
            description:
                L10n.text(
                    "Click a shortcut, then press a key combination. Delete turns it off; Escape cancels. Shortcuts work across apps."
                )
        ) { stack in
            stack.addArrangedSubview(SettingsLayout.heading(L10n.text("Recording")))
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
                            L10n.text("That shortcut is already assigned to another Record action.")
                    }
                }
                button.onInvalid = { [weak self] in self?.recordingShortcutMessage.stringValue = $0
                }
                recordingShortcutButtons[action] = button
                stack.addArrangedSubview(SettingsLayout.row(action.title, button))
            }
            recordingShortcutMessage.textColor = .systemOrange
            stack.addArrangedSubview(recordingShortcutMessage)
            stack.addArrangedSubview(SettingsLayout.heading(L10n.text("Screenshots")))
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
                        title: L10n.text("Restore Screenshot Defaults"), target: self,
                        action: #selector(restoreScreenshotDefaults)),
                    NSButton(
                        title: L10n.text("macOS Keyboard Shortcuts…"), target: self,
                        action: #selector(openSystemShortcuts)),
                ]))
        }
    }

    @objc func showDiagnostics() { onShowDiagnostics?() }
}
