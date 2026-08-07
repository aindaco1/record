import AppKit
import ArgumentParser
import CoreServices
import Foundation
import RecordCapture
import RecordCore
import RecordMedia

@main
struct RecordCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "record",
        abstract:
            "Local meeting recorder + transcriber. Records mic and system audio as two tracks, then transcribes on-device.",
        subcommands: [Run.self, Doctor.self, Install.self, InspectSession.self],
        defaultSubcommand: Run.self
    )
}

struct Run: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Run the menu-bar daemon (default)."
    )

    @Option(name: .long, help: "Recordings root directory (overrides the config file).")
    var out: String?

    func run() throws {
        FluidAudioOfflinePolicy.enforce()
        // ArgumentParser invokes run() on the main thread; promote that fact
        // to the type system so AppKit calls are cleanly isolated.
        try MainActor.assumeIsolated { try runMain() }
    }

    @MainActor
    private func runMain() throws {
        let root = Config.resolveRoot(cliOverride: out)

        // Non-blocking: permissions prompt on first recording, so warnings at
        // startup are informational, not fatal.
        let checks = DoctorReport.run(recordingsRoot: root)
        if !DoctorReport.allOK(checks) {
            FileHandle.standardError.write(Data("startup checks failed:\n".utf8))
            DoctorReport.print(checks)
            throw ExitCode(1)
        }

        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let controller = AppController(root: root)
        let applicationDelegate = RecordApplicationDelegate(controller: controller)
        app.delegate = applicationDelegate

        let sigint = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        sigint.setEventHandler {
            FileHandle.standardError.write(Data("\nshutting down\n".utf8))
            MainActor.assumeIsolated { controller.shutdown() }
        }
        sigint.resume()
        signal(SIGINT, SIG_IGN)

        FileHandle.standardError.write(
            Data(
                "Record up · recordings → \(root.path) · ^C to quit\n".utf8
            ))
        withExtendedLifetime(applicationDelegate) {
            app.run()
        }
    }
}

@MainActor
final class RecordApplicationDelegate: NSObject, NSApplicationDelegate {
    private weak var controller: AppController?

    init(controller: AppController) {
        self.controller = controller
    }

    func applicationShouldTerminate(
        _ sender: NSApplication
    ) -> NSApplication.TerminateReply {
        if controller?.handleTerminationRequest(
            appleEvent: NSAppleEventManager.shared().currentAppleEvent
        ) == true {
            return .terminateCancel
        }
        return .terminateNow
    }
}

struct Doctor: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Check microphone, system audio, and recordings folder."
    )

    func run() throws {
        FluidAudioOfflinePolicy.enforce()
        let checks = DoctorReport.run(recordingsRoot: Config.resolveRoot(cliOverride: nil))
        DoctorReport.print(checks)
        if !DoctorReport.allOK(checks) {
            throw ExitCode(1)
        }
    }
}

/// Owns the menu bar, the current recording session, and the elapsed-time
/// ticker. All state transitions happen on the main actor.
@MainActor
final class AppController {
    private enum ActiveRecording {
        case audio(RecordingSession)
        case video(VideoRecordingSession)

        var startedAt: Date {
            switch self {
            case .audio(let session): session.startedAt
            case .video(let session): session.startedAt
            }
        }

        var mode: RecordingMode {
            switch self {
            case .audio: .audioOnly
            case .video: .screen
            }
        }
    }

    private let root: URL
    private let menuBar = MenuBarController()
    private let notifications: RecordNotificationCenter
    private let transcription: TranscriptionCoordinator
    private let screenRecordingPermission = ScreenRecordingPermissionController()
    private let exportDirectoryAccess = ExportDirectoryAccess()
    private let capturePrivacyPreferences = CapturePrivacyPreferences()
    private let recordingNamePreferences = RecordingNamePreferences()
    private var exportDirectoryLease: ExportDirectoryLease?
    private var activeRecording: ActiveRecording?
    private var ticker: Timer?
    private var videoStartTask: Task<Void, Never>?
    private var videoStopTask: Task<Void, Never>?
    private var pendingVideoStop = false
    private var quitAfterStop = false
    private var relaunchAfterPrivacySettingsQuit = false
    private var videoExportName: String?
    private var lastFinishedVideoURL: URL?

    init(root: URL) {
        self.root = root
        let notifications = RecordNotificationCenter(recordingsRoot: root)
        self.notifications = notifications
        transcription = TranscriptionCoordinator { notification in
            notifications.post(notification)
        }
        menuBar.onToggle = { [weak self] in self?.toggle() }
        menuBar.onStartAudioOnly = { [weak self] in self?.startAudioSession() }
        menuBar.onManageScreenRecordingPermission = { [weak self] in
            self?.manageScreenRecordingPermission()
        }
        menuBar.onToggleCapturePrivacy = { [weak self] in self?.toggleCapturePrivacy($0) }
        menuBar.onToggleRecordingName = { [weak self] in self?.toggleRecordingName() }
        menuBar.onEditRecordingNameTemplate = { [weak self] in
            self?.editRecordingNameTemplate()
        }
        menuBar.onOpenLastVideoInGifski = { [weak self] in self?.openLastVideoInGifski() }
        menuBar.onSelectTranscriptionEngine = { [weak self] in
            self?.selectTranscriptionEngine($0)
        }
        menuBar.onOpenFolder = { [weak self] in self?.openFolder() }
        menuBar.onChooseExportFolder = { [weak self] in self?.chooseExportFolder() }
        menuBar.onRestart = { [weak self] in self?.restart() }
        menuBar.onQuit = { [weak self] in self?.shutdown() }
        menuBar.update(recording: false, elapsed: nil)
        refreshScreenRecordingPermissionMenu()
        refreshCapturePrivacyMenu()
        refreshRecordingNameMenu()
        refreshGifskiMenu()
        refreshTranscriptionEngineMenu()
        restoreExportFolderAccess()

        Task { [transcription, root] in
            await transcription.setStatusHandler { status in
                Task { @MainActor [weak self] in
                    self?.showTranscription(status)
                }
            }
            await transcription.resumePending(root: root)
        }
    }

    /// Stop any live session cleanly (finalizing files) and exit.
    func shutdown() {
        quitAfterStop = true
        guard activeRecording != nil else {
            NSApp.terminate(nil)
            return
        }
        stopSession()
    }

    private func toggle() {
        if activeRecording == nil {
            startVideoSession()
        } else {
            stopSession()
        }
    }

    private func startAudioSession() {
        guard activeRecording == nil else { return }
        do {
            let newSession = try RecordingSession(root: root)
            try newSession.start()
            activeRecording = .audio(newSession)
            FileHandle.standardError.write(Data("● recording → \(newSession.dir.path)\n".utf8))
        } catch {
            FileHandle.standardError.write(Data("recording start failed: \(error)\n".utf8))
            postNotification(
                title: "Audio recording couldn’t start",
                body: "Check the microphone permission and try again.",
                directory: root
            )
            return
        }

        menuBar.update(recording: true, elapsed: "0:00", mode: .audioOnly)
        startTicker()
    }

    private func startVideoSession() {
        guard activeRecording == nil else { return }
        switch screenRecordingPermission.prepareForCapture() {
        case .ready:
            break
        case .setupStarted:
            relaunchAfterPrivacySettingsQuit = true
            refreshScreenRecordingPermissionMenu()
            return
        case .cancelled:
            refreshScreenRecordingPermissionMenu()
            return
        }
        refreshScreenRecordingPermissionMenu()
        if exportDirectoryLease == nil {
            chooseExportFolder()
        }

        let newSession: VideoRecordingSession
        do {
            newSession = try VideoRecordingSession(root: root) { [weak self] event in
                Task { @MainActor [weak self] in self?.handleVideoEvent(event) }
            }
        } catch {
            reportRecordingStartFailure(error)
            return
        }

        videoExportName = recordingNamePreferences.renderName(
            at: newSession.startedAt,
            clipboard: NSPasteboard.general.string(forType: .string)
        )
        activeRecording = .video(newSession)
        pendingVideoStop = false
        menuBar.updatePreparingScreenRecording()
        videoStartTask = Task { [weak self, newSession] in
            do {
                var configuration = try VideoCaptureProfile.mainDisplayConfiguration()
                configuration.privacy = self?.capturePrivacyPreferences.configuration ?? .init()
                try await newSession.start(configuration: configuration)
                guard let self else { return }
                self.videoStartTask = nil
                if self.pendingVideoStop {
                    self.stopVideoSession(newSession)
                } else {
                    FileHandle.standardError.write(
                        Data("● screen recording → \(newSession.dir.path)\n".utf8)
                    )
                    self.menuBar.update(recording: true, elapsed: "0:00", mode: .screen)
                    self.startTicker()
                }
            } catch {
                guard let self else { return }
                self.videoStartTask = nil
                self.finishVideoStartFailure(error, session: newSession)
            }
        }
    }

    private func startTicker() {
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func stopSession() {
        guard let activeRecording else { return }
        switch activeRecording {
        case .audio(let session):
            stopAudioSession(session)
        case .video(let session):
            if videoStartTask != nil {
                pendingVideoStop = true
                menuBar.updateStoppingRecording()
            } else {
                stopVideoSession(session)
            }
        }
    }

    private func stopAudioSession(_ session: RecordingSession) {
        let finalized: Bool
        do {
            try session.stop()
            finalized = true
        } catch {
            finalized = false
            FileHandle.standardError.write(
                Data(
                    "recording finalization failed: \(error)\n".utf8
                ))
            postNotification(
                title: "Audio recording needs recovery",
                body: "The audio is safe. Click to open the recording folder.",
                directory: session.dir
            )
        }
        let elapsed = Self.format(Date().timeIntervalSince(session.startedAt))
        FileHandle.standardError.write(
            Data(
                "○ stopped · \(elapsed) · \(session.dir.path)\n".utf8
            ))
        activeRecording = nil
        ticker?.invalidate()
        ticker = nil
        menuBar.update(recording: false, elapsed: nil)

        if finalized {
            let dir = session.dir
            Task { [transcription] in await transcription.enqueue(dir) }
        }
        terminateIfRequested()
    }

    private func stopVideoSession(_ session: VideoRecordingSession) {
        guard videoStopTask == nil else { return }
        menuBar.updateStoppingRecording()
        ticker?.invalidate()
        ticker = nil
        videoStopTask = Task { [weak self, session] in
            let result: Result<VideoRecordingOutcome, Error>
            do {
                result = .success(try await session.stop())
            } catch {
                result = .failure(error)
            }
            guard let self else { return }
            self.finishVideoStop(result, session: session)
        }
    }

    private func finishVideoStop(
        _ result: Result<VideoRecordingOutcome, Error>,
        session: VideoRecordingSession
    ) {
        videoStopTask = nil
        pendingVideoStop = false
        let preferredExportName =
            videoExportName
            ?? RecordingNameTemplate.legacyValue.render(at: session.startedAt)
        videoExportName = nil
        if case .video(let active) = activeRecording, active === session {
            activeRecording = nil
        }
        menuBar.update(recording: false, elapsed: nil)

        switch result {
        case .success(let outcome):
            logIngress(outcome.ingress)
            if outcome.state == .finalized, let mediaURL = outcome.mediaURL {
                lastFinishedVideoURL = publishVideo(
                    mediaURL,
                    preferredBaseName: preferredExportName
                )
                refreshGifskiMenu()
            } else {
                postNotification(
                    title: "Screen recording preserved",
                    body: "Capture stopped early, but the available video is safe.",
                    directory: outcome.sessionDirectory
                )
            }
        case .failure(let error):
            FileHandle.standardError.write(Data("video finalization failed: \(error)\n".utf8))
            postNotification(
                title: "Screen recording needs recovery",
                body: "The available media is safe. Click to open the recording folder.",
                directory: session.dir
            )
        }
        terminateIfRequested()
    }

    private func publishVideo(_ mediaURL: URL, preferredBaseName: String) -> URL {
        let sessionDirectory = mediaURL.deletingLastPathComponent()
        guard let exportDirectoryLease else {
            postNotification(
                title: "Screen recording ready",
                body: "Saved locally. Click to open the recording folder.",
                directory: sessionDirectory
            )
            return mediaURL
        }
        do {
            let exportedURL = try FinishedVideoExporter.export(
                sourceURL: mediaURL,
                to: exportDirectoryLease.url,
                preferredBaseName: preferredBaseName
            )
            FileHandle.standardError.write(Data("○ video exported → \(exportedURL.path)\n".utf8))
            postNotification(
                title: "Screen recording ready",
                body:
                    "Saved a copy to \(exportedURL.deletingLastPathComponent().lastPathComponent). Click to open the recording folder.",
                directory: sessionDirectory
            )
            return exportedURL
        } catch {
            FileHandle.standardError.write(Data("video export failed: \(error)\n".utf8))
            postNotification(
                title: "Screen recording saved locally",
                body: "The Desktop copy failed, but the original video is safe.",
                directory: sessionDirectory
            )
            return mediaURL
        }
    }

    private func handleVideoEvent(_ event: ScreenCaptureEvent) {
        switch event {
        case .stopRequested:
            stopSession()
        case .failed(let failure):
            FileHandle.standardError.write(
                Data("screen capture failed: \(failure.summary)\n".utf8)
            )
            stopSession()
        }
    }

    private func finishVideoStartFailure(_ error: Error, session: VideoRecordingSession) {
        if case .video(let active) = activeRecording, active === session {
            activeRecording = nil
        }
        pendingVideoStop = false
        videoExportName = nil
        menuBar.update(recording: false, elapsed: nil)
        if Self.captureFailure(from: error)?.code == .permissionDenied {
            screenRecordingPermission.presentCaptureDenial()
            refreshScreenRecordingPermissionMenu()
        } else {
            reportRecordingStartFailure(error, directory: session.dir)
        }
        terminateIfRequested()
    }

    private func reportRecordingStartFailure(_ error: Error, directory: URL? = nil) {
        FileHandle.standardError.write(Data("recording start failed: \(error)\n".utf8))
        postNotification(
            title: "Screen recording couldn’t start",
            body: Self.startFailureMessage(for: error),
            directory: directory ?? root
        )
    }

    private static func captureFailure(from error: Error) -> CaptureFailure? {
        if case .captureFailed(let failure) = error as? VideoRecordingSession.SessionError {
            return failure
        }
        if case .captureFailed(let failure) = error as? ScreenCaptureAdapterError {
            return failure
        }
        return nil
    }

    static func startFailureMessage(for error: Error) -> String {
        switch captureFailure(from: error)?.code {
        case .sourceUnavailable:
            "The selected screen or window is no longer available. Choose it again and retry."
        case .deviceDisconnected:
            "An audio device became unavailable. Reconnect it and try again."
        case .encoderFailed, .writerFailed:
            "Record couldn’t prepare the local video file. The failed session was preserved."
        case .permissionDenied:
            "Screen Recording permission is required. Audio-only recording still works."
        case .internalFailure, nil:
            "Record couldn’t prepare screen capture. The failed session was preserved."
        }
    }

    private func toggleCapturePrivacy(_ feature: CapturePrivacyFeature) {
        guard activeRecording == nil else { return }
        capturePrivacyPreferences.toggle(feature)
        refreshCapturePrivacyMenu()
    }

    private func refreshCapturePrivacyMenu() {
        menuBar.updateCapturePrivacy(capturePrivacyPreferences.configuration)
    }

    private func toggleRecordingName() {
        recordingNamePreferences.isEnabled.toggle()
        refreshRecordingNameMenu()
    }

    private func editRecordingNameTemplate() {
        let input = NSTextField(string: recordingNamePreferences.template.rawValue)
        input.frame = NSRect(x: 0, y: 0, width: 420, height: 24)
        input.placeholderString = "{date} at {time} - {color} {animal}"

        let alert = NSAlert()
        alert.messageText = "Recording Name Template"
        alert.informativeText =
            "Tokens: {date}, {time}, {clipboard}, {color}, {adjective}, {animal}, "
            + "{country}, {name}, {starWars}. Clipboard is read only when requested."
        alert.accessoryView = input
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            try recordingNamePreferences.setTemplate(input.stringValue)
            recordingNamePreferences.isEnabled = true
            refreshRecordingNameMenu()
        } catch {
            let failure = NSAlert()
            failure.alertStyle = .warning
            failure.messageText = "Invalid Recording Name Template"
            failure.informativeText = "Use only the supported tokens and balanced braces."
            failure.runModal()
        }
    }

    private func refreshRecordingNameMenu() {
        menuBar.updateRecordingName(
            enabled: recordingNamePreferences.isEnabled,
            template: recordingNamePreferences.template.rawValue
        )
    }

    private func refreshGifskiMenu() {
        menuBar.updateGifski(
            available: GifskiHandoff.isAvailable,
            hasFinishedVideo: lastFinishedVideoURL != nil
        )
    }

    private func openLastVideoInGifski() {
        guard let lastFinishedVideoURL else { return }
        do {
            try GifskiHandoff.open(videoURL: lastFinishedVideoURL) { [weak self] result in
                if case .failure = result, let self {
                    self.postNotification(
                        title: "Gifski couldn’t open the video",
                        body: "The recording is safe and can be opened manually.",
                        directory: self.recordingDirectory(for: lastFinishedVideoURL)
                    )
                }
            }
        } catch {
            postNotification(
                title: "Gifski is unavailable",
                body: "Install Gifski, then try opening the recording again.",
                directory: recordingDirectory(for: lastFinishedVideoURL)
            )
        }
    }

    private func logIngress(_ snapshot: MediaIngressSnapshot) {
        let dropped = snapshot.tracks.values.reduce(0) {
            $0 + $1.droppedForBackpressure + $1.droppedByProcessor
        }
        FileHandle.standardError.write(
            Data("media ingress completed · \(dropped) dropped sample(s)\n".utf8)
        )
    }

    private func terminateIfRequested() {
        if quitAfterStop {
            NSApp.terminate(nil)
        }
    }

    private func showTranscription(_ status: TranscriptionCoordinator.Status) {
        switch status {
        case .idle:
            menuBar.updateTranscription(nil)
        case .transcribing(let name, let queued):
            menuBar.updateTranscription(
                queued > 0 ? "transcribing \(name) · \(queued) queued" : "transcribing \(name)"
            )
        case .failed(let name):
            menuBar.updateTranscription("transcription failed · \(name)")
        }
    }

    private func selectTranscriptionEngine(_ engine: TranscriptionEngineOption) {
        TranscriptionPreferences.select(engine)
        refreshTranscriptionEngineMenu()
    }

    private func refreshTranscriptionEngineMenu() {
        menuBar.updateTranscriptionEngine(
            Config.transcriptionSelection().engine,
            macWhisperAvailable: MacWhisperExecutable.resolve(
                configuredPath: Config.transcriptionExecutable()
            ) != nil
        )
    }

    private func tick() {
        guard let activeRecording else { return }
        menuBar.update(
            recording: true,
            elapsed: Self.format(Date().timeIntervalSince(activeRecording.startedAt)),
            mode: activeRecording.mode
        )
    }

    private func openFolder() {
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        NSWorkspace.shared.open(root)
    }

    private func manageScreenRecordingPermission() {
        if screenRecordingPermission.setupPermissions() {
            relaunchAfterPrivacySettingsQuit = true
        }
        refreshScreenRecordingPermissionMenu()
    }

    func handleTerminationRequest(
        appleEvent: NSAppleEventDescriptor?
    ) -> Bool {
        guard relaunchAfterPrivacySettingsQuit else { return false }
        guard Self.isPrivacySettingsQuitEvent(appleEvent) else { return false }

        relaunchAfterPrivacySettingsQuit = false
        restart()
        return true
    }

    static func shouldRelaunchAfterPrivacySettingsQuit(
        eventClass: AEEventClass,
        eventID: AEEventID,
        senderBundleIdentifier: String?
    ) -> Bool {
        guard eventClass == AEEventClass(kCoreEventClass) else { return false }
        guard eventID == AEEventID(kAEQuitApplication) else { return false }
        return [
            "com.apple.settings.PrivacySecurity.extension",
            "com.apple.systempreferences",
        ].contains(senderBundleIdentifier)
    }

    private static func isPrivacySettingsQuitEvent(
        _ event: NSAppleEventDescriptor?
    ) -> Bool {
        guard let event else { return false }
        guard
            let senderPID = event.attributeDescriptor(
                forKeyword: AEKeyword(keySenderPIDAttr)
            )?.int32Value
        else { return false }

        let senderBundleIdentifier = NSRunningApplication(
            processIdentifier: pid_t(senderPID)
        )?.bundleIdentifier
        return shouldRelaunchAfterPrivacySettingsQuit(
            eventClass: event.eventClass,
            eventID: event.eventID,
            senderBundleIdentifier: senderBundleIdentifier
        )
    }

    private func refreshScreenRecordingPermissionMenu() {
        menuBar.updateScreenRecordingPermission(screenRecordingPermission.presentation)
    }

    private func restart() {
        guard activeRecording == nil else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.createsNewApplicationInstance = true
        let applicationURL = Bundle.main.bundleURL

        Task { @MainActor [weak self] in
            do {
                _ = try await NSWorkspace.shared.openApplication(
                    at: applicationURL,
                    configuration: configuration
                )
                NSApp.terminate(nil)
            } catch {
                self?.postNotification(
                    title: "Record couldn’t restart",
                    body: "Quit Record from the menu bar, then open it again.",
                    directory: self?.root
                )
            }
        }
    }

    private func postNotification(
        title: String,
        body: String,
        directory: URL?
    ) {
        notifications.post(
            RecordNotification(
                title: title,
                body: body,
                destinationDirectory: directory ?? root
            )
        )
    }

    private func recordingDirectory(for url: URL) -> URL {
        let candidate = url.standardizedFileURL.deletingLastPathComponent()
        return candidate.deletingLastPathComponent() == root.standardizedFileURL
            ? candidate
            : root
    }

    private func restoreExportFolderAccess() {
        do {
            exportDirectoryLease = try exportDirectoryAccess.restore()
        } catch {
            exportDirectoryAccess.forgetStoredSelection()
            FileHandle.standardError.write(
                Data("saved export folder access was reset: \(error)\n".utf8)
            )
        }
        menuBar.updateExportDirectory(
            exportDirectoryLease?.url ?? exportDirectoryAccess.suggestedDirectory
        )
    }

    private func chooseExportFolder() {
        do {
            guard let selection = try exportDirectoryAccess.choose() else { return }
            exportDirectoryLease = selection
            menuBar.updateExportDirectory(selection.url)
        } catch {
            FileHandle.standardError.write(Data("export folder selection failed: \(error)\n".utf8))
            postNotification(
                title: "Export folder unavailable",
                body: "Choose the export folder again. Existing recordings are unaffected.",
                directory: root
            )
        }
    }

    private static func format(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }
}
