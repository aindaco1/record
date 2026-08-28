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
        subcommands: [Run.self, Doctor.self, InspectSession.self],
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller?.prepareNotifications()
    }

    func applicationShouldTerminate(
        _ sender: NSApplication
    ) -> NSApplication.TerminateReply {
        if controller?.handleTerminationRequest(
            appleEvent: NSAppleEventManager.shared().currentAppleEvent
        ) == true {
            return .terminateCancel
        }
        return controller?.prepareForTermination() == false
            ? .terminateCancel
            : .terminateNow
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

    private enum SessionPublicationResult: Sendable {
        case exported(FinishedSessionExport, cleanupWarning: String?)
        case exportFailed(String)
    }

    private let root: URL
    private let menuBar = MenuBarController()
    private let updateController = AppUpdateController()
    private let launchAtLoginController = LaunchAtLoginController()
    private let notifications: RecordNotificationCenter
    private let transcription: TranscriptionCoordinator
    private let recordingPermission: RecordingPermissionController
    private let pendingRecordingIntentStore: PendingRecordingIntentStore
    private let exportDirectoryAccess = ExportDirectoryAccess()
    private let capturePrivacyPreferences = CapturePrivacyPreferences()
    private let recordingNamePreferences = RecordingNamePreferences()
    private let screenCaptureSourcePreferences = ScreenCaptureSourcePreferences()
    private let systemScreenCapturePicker = SystemScreenCapturePicker()
    private let regionSelectionController = RegionSelectionController()
    private var exportDirectoryLease: ExportDirectoryLease?
    private var activeRecording: ActiveRecording?
    private var ticker: Timer?
    private var audioStopTask: Task<Void, Never>?
    private var videoStartTask: Task<Void, Never>?
    private var videoRotationTask: Task<Void, Never>?
    private var videoStopTask: Task<Void, Never>?
    private var sessionPublishTask: Task<Void, Never>?
    private var recentRecordingRefreshTask: Task<Void, Never>?
    private var permissionTask: Task<Void, Never>?
    private var permissionFlow = RecordingPermissionFlowState()
    private var pendingVideoStop = false
    private var videoPaused = false
    private var videoElapsedClock = RecordingElapsedClock()
    private var quitAfterStop = false
    private var recordingExportName: String?
    private var lastFinishedVideoURL: URL?
    private var lastFinishedRecordingDirectory: URL?
    private var presentedMissingModelPrompt = false
    private var modelImportInProgress = false

    init(
        root: URL,
        recordingPermission: RecordingPermissionController =
            RecordingPermissionController(),
        pendingRecordingIntentStore: PendingRecordingIntentStore =
            PendingRecordingIntentStore()
    ) {
        self.root = root
        self.recordingPermission = recordingPermission
        self.pendingRecordingIntentStore = pendingRecordingIntentStore
        let recordingToResume = pendingRecordingIntentStore.consume()
        let notifications = RecordNotificationCenter(recordingsRoot: root)
        self.notifications = notifications
        transcription = TranscriptionCoordinator { notification in
            notifications.post(notification)
        }
        menuBar.onToggle = { [weak self] in self?.toggle() }
        menuBar.onStartAudioOnly = { [weak self] in
            self?.requestRecording(.audioOnly)
        }
        menuBar.onPauseResume = { [weak self] in self?.toggleVideoPause() }
        menuBar.onSelectScreenSource = { [weak self] in
            self?.selectScreenCaptureSource($0)
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
        menuBar.onToggleTranscriptRefinement = { [weak self] in
            self?.toggleTranscriptRefinement()
        }
        menuBar.onSetUpParakeetModel = { [weak self] in
            self?.presentParakeetModelSetup()
        }
        menuBar.onRetryTranscription = { [weak self] in self?.retryTranscription() }
        menuBar.onOpenFolder = { [weak self] in self?.openFolder() }
        menuBar.onOpenLastRecording = { [weak self] in self?.openLastRecording() }
        menuBar.onChooseExportFolder = { [weak self] in self?.chooseExportFolder() }
        menuBar.onCheckForUpdates = { [weak self] in self?.checkForUpdates() }
        menuBar.onToggleLaunchAtLogin = { [weak self] in self?.toggleLaunchAtLogin() }
        menuBar.onQuit = { [weak self] in self?.shutdown() }
        menuBar.update(recording: false, elapsed: nil)
        menuBar.updateScreenCaptureSource(screenCaptureSourcePreferences.selected)
        menuBar.updateLastRecording(available: false)
        refreshCapturePrivacyMenu()
        refreshRecordingNameMenu()
        refreshGifskiMenu()
        refreshTranscriptionEngineMenu()
        refreshLaunchAtLoginMenu()
        restoreExportFolderAccess()
        refreshRecentRecordingMenu()
        let restoredExportRoot = exportDirectoryLease?.url

        Task { [transcription, root, self] in
            await transcription.setStatusHandler { [weak controller = self] status in
                Task { @MainActor [controller] in
                    controller?.showTranscription(status)
                }
            }
            await transcription.resumePending(root: root)
            if let restoredExportRoot {
                await transcription.resumePending(
                    root: restoredExportRoot,
                    recoverInterrupted: false
                )
            }
        }

        if let recordingToResume {
            DispatchQueue.main.async { [weak self] in
                self?.requestRecording(recordingToResume, resumingAfterRestart: true)
            }
        }
    }

    /// Request notification access after launch, before the first completed
    /// recording needs to publish a ready event.
    func prepareNotifications() {
        Task { [notifications] in
            await notifications.prepareAuthorization()
        }
        presentMissingParakeetModelIfNeeded()
    }

    /// Stop any live session cleanly (finalizing files) and exit.
    func shutdown() {
        quitAfterStop = true
        if activeRecording == nil, let videoStartTask {
            videoStartTask.cancel()
            self.videoStartTask = nil
            menuBar.update(recording: false, elapsed: nil)
        }
        guard activeRecording != nil || sessionPublishTask != nil || videoRotationTask != nil else {
            NSApp.terminate(nil)
            return
        }
        if activeRecording != nil {
            stopSession()
        }
    }

    /// Route every termination request through the same finalization path as
    /// the Quit menu. This also protects an active capture if an updater asks
    /// Record to relaunch after installing a signed release.
    func prepareForTermination() -> Bool {
        guard
            activeRecording != nil || sessionPublishTask != nil || videoStartTask != nil
                || videoRotationTask != nil
        else {
            return true
        }
        shutdown()
        return false
    }

    private func toggle() {
        if activeRecording == nil {
            requestRecording(.screen)
        } else {
            stopSession()
        }
    }

    private func requestRecording(
        _ mode: RecordingMode,
        resumingAfterRestart: Bool = false
    ) {
        guard activeRecording == nil,
            permissionTask == nil,
            sessionPublishTask == nil,
            videoStartTask == nil
        else { return }

        // A second Start click after macOS returned a stale in-process denial
        // is an explicit fallback restart. Normally Privacy & Security sends
        // the quit event itself as soon as the user enables the toggle.
        if permissionFlow.begin(
            mode,
            resumingAfterRestart: resumingAfterRestart
        ) == .restart {
            restart(resuming: mode)
            return
        }

        menuBar.updateRequestingPermissions(for: mode)
        permissionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let preparation = await self.recordingPermission.prepare(for: mode)
            guard !Task.isCancelled else { return }
            self.permissionTask = nil

            switch preparation {
            case .ready:
                self.permissionFlow.clear()
                switch mode {
                case .screen: self.startVideoSessionAfterPermission()
                case .audioOnly:
                    self.startAudioSessionAfterPermission(
                        preparedSystemAudioTap: self.recordingPermission
                            .takePreparedSystemAudioTap()
                    )
                }
            case .waitingForRestart(let blocker):
                self.menuBar.update(recording: false, elapsed: nil)
                if resumingAfterRestart,
                    !self.recordingPermission.presentSettingsRequired(for: blocker)
                {
                    self.permissionFlow.clear()
                }
            case .needsSettings(let blocker):
                self.menuBar.update(recording: false, elapsed: nil)
                if !self.recordingPermission.presentSettingsRequired(for: blocker) {
                    self.permissionFlow.clear()
                }
            }
        }
    }

    private func startAudioSessionAfterPermission(
        preparedSystemAudioTap: PreparedSystemAudioTap?
    ) {
        guard activeRecording == nil else { return }
        ensureExportFolderAccess()
        do {
            let newSession = try RecordingSession(
                root: root,
                preparedSystemAudioTap: preparedSystemAudioTap
            ) { [weak self] event in
                Task { @MainActor [weak self] in self?.handleCaptureHealth(event) }
            }
            recordingExportName = recordingNamePreferences.renderName(
                at: newSession.startedAt,
                clipboard: NSPasteboard.general.string(forType: .string)
            )
            try newSession.start()
            activeRecording = .audio(newSession)
            FileHandle.standardError.write(Data("● recording → \(newSession.dir.path)\n".utf8))
        } catch {
            recordingExportName = nil
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

    private func startVideoSessionAfterPermission() {
        guard activeRecording == nil, videoStartTask == nil else { return }
        ensureExportFolderAccess()
        pendingVideoStop = false
        menuBar.updatePreparingScreenRecording()
        videoStartTask = Task { [weak self] in
            guard let self else { return }
            var newSession: VideoRecordingSession?
            do {
                let prepared = try await self.prepareVideoCaptureSource()
                try Task.checkCancellation()
                let session = try VideoRecordingSession(root: self.root) { [weak self] event in
                    Task { @MainActor [weak self] in self?.handleVideoEvent(event) }
                }
                newSession = session
                self.recordingExportName = self.recordingNamePreferences.renderName(
                    at: session.startedAt,
                    clipboard: NSPasteboard.general.string(forType: .string)
                )
                self.activeRecording = .video(session)
                try await session.start(
                    configuration: prepared.configuration,
                    selection: prepared.selection
                )
                self.videoStartTask = nil
                if self.pendingVideoStop {
                    self.stopVideoSession(session)
                } else {
                    FileHandle.standardError.write(
                        Data("● screen recording → \(session.dir.path)\n".utf8)
                    )
                    self.videoPaused = false
                    self.videoElapsedClock.start(at: Date())
                    self.menuBar.update(recording: true, elapsed: "0:00", mode: .screen)
                    self.startTicker()
                }
            } catch {
                self.videoStartTask = nil
                if let newSession {
                    self.finishVideoStartFailure(error, session: newSession)
                } else {
                    self.recordingExportName = nil
                    self.pendingVideoStop = false
                    self.menuBar.update(recording: false, elapsed: nil)
                    if !Self.isSourceSelectionCancellation(error) {
                        self.reportRecordingStartFailure(error)
                    }
                    self.terminateIfRequested()
                }
            }
        }
    }

    private func prepareVideoCaptureSource() async throws -> (
        configuration: CaptureConfiguration,
        selection: SystemScreenCaptureSelection?
    ) {
        let privacy = capturePrivacyPreferences.configuration
        switch screenCaptureSourcePreferences.selected {
        case .mainDisplay:
            var configuration = try VideoCaptureProfile.mainDisplayConfiguration()
            configuration.privacy = privacy
            return (configuration, nil)
        case .systemPicker:
            let selection = try await systemScreenCapturePicker.select(
                mode: .source,
                privacy: privacy
            )
            return (try selection.configuration(privacy: privacy), selection)
        case .region:
            let region = try await regionSelectionController.selectRegion()
            return (
                try VideoCaptureProfile.regionConfiguration(
                    selection: region,
                    privacy: privacy
                ),
                nil
            )
        }
    }

    private static func isSourceSelectionCancellation(_ error: Error) -> Bool {
        error is CancellationError
            || error as? SystemScreenCapturePickerError == .cancelled
            || error as? RegionSelectionError == .cancelled
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
            if videoStartTask != nil || videoRotationTask != nil {
                pendingVideoStop = true
                menuBar.updateStoppingRecording()
            } else {
                stopVideoSession(session)
            }
        }
    }

    private func stopAudioSession(_ session: RecordingSession) {
        guard audioStopTask == nil else { return }
        let endedAt = Date()
        ticker?.invalidate()
        ticker = nil
        menuBar.updateSavingRecording()
        audioStopTask = Task { [weak self, session] in
            let result: Result<Void, Error>
            do {
                result = .success(try await session.stop(endedAt: endedAt))
            } catch {
                result = .failure(error)
            }
            self?.finishAudioStop(result, session: session, endedAt: endedAt)
        }
    }

    private func finishAudioStop(
        _ result: Result<Void, Error>,
        session: RecordingSession,
        endedAt: Date
    ) {
        audioStopTask = nil
        let finalized: Bool
        switch result {
        case .success:
            finalized = true
        case .failure(let error):
            finalized = false
            FileHandle.standardError.write(
                Data("recording finalization failed: \(error)\n".utf8)
            )
            postNotification(
                title: "Audio recording needs recovery",
                body: "The audio is safe. Click to open the recording folder.",
                directory: session.dir
            )
        }
        let elapsed = Self.format(endedAt.timeIntervalSince(session.startedAt))
        FileHandle.standardError.write(
            Data(
                "○ stopped · \(elapsed) · \(session.dir.path)\n".utf8
            ))
        activeRecording = nil
        menuBar.update(recording: false, elapsed: nil)

        if finalized {
            let preferredExportName =
                recordingExportName
                ?? RecordingNameTemplate.legacyValue.render(at: session.startedAt)
            recordingExportName = nil
            beginSessionPublication(
                sessionDirectory: session.dir,
                mode: .audioOnly,
                originalVideoURL: nil,
                preferredBaseName: preferredExportName
            )
            return
        }
        recordingExportName = nil
        terminateIfRequested()
    }

    private func stopVideoSession(_ session: VideoRecordingSession) {
        guard videoStopTask == nil else { return }
        _ = videoElapsedClock.stop(at: Date())
        videoPaused = false
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
        videoRotationTask = nil
        pendingVideoStop = false
        let preferredExportName =
            recordingExportName
            ?? RecordingNameTemplate.legacyValue.render(at: session.startedAt)
        recordingExportName = nil
        if case .video(let active) = activeRecording, active === session {
            activeRecording = nil
        }
        menuBar.update(recording: false, elapsed: nil)

        switch result {
        case .success(let outcome):
            logIngress(outcome.ingress)
            if outcome.state == .finalized, let mediaURL = outcome.mediaURL {
                beginSessionPublication(
                    sessionDirectory: outcome.sessionDirectory,
                    mode: .screen,
                    originalVideoURL: mediaURL,
                    preferredBaseName: preferredExportName
                )
                return
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

    private func beginSessionPublication(
        sessionDirectory: URL,
        mode: RecordingMode,
        originalVideoURL: URL?,
        preferredBaseName: String
    ) {
        guard let exportDirectoryLease else {
            if let originalVideoURL {
                lastFinishedVideoURL = originalVideoURL
            }
            setLastFinishedRecordingDirectory(sessionDirectory)
            refreshGifskiMenu()
            postNotification(
                title: Self.readyNotificationTitle(for: mode),
                body: "Saved locally. Click to open the recording folder.",
                directory: sessionDirectory
            )
            Task { [transcription] in await transcription.enqueue(sessionDirectory) }
            terminateIfRequested()
            return
        }

        menuBar.updateSavingRecording()
        let exportRoot = exportDirectoryLease.url
        let recordingsRoot = root
        let worker = Task.detached(priority: .utility) {
            () -> SessionPublicationResult in
            do {
                let export = try FinishedSessionExporter.export(
                    sourceDirectory: sessionDirectory,
                    to: exportRoot,
                    preferredDirectoryName: preferredBaseName
                )
                var cleanupWarning: String?
                do {
                    try PrivateSessionCleaner.removeFinalizedSession(
                        sessionDirectory,
                        under: recordingsRoot
                    )
                } catch {
                    cleanupWarning = String(describing: error)
                }
                return .exported(export, cleanupWarning: cleanupWarning)
            } catch {
                return .exportFailed(String(describing: error))
            }
        }
        sessionPublishTask = Task { [weak self] in
            let result = await worker.value
            self?.finishSessionPublication(
                result,
                mode: mode,
                originalVideoURL: originalVideoURL,
                originalSessionDirectory: sessionDirectory,
                exportRoot: exportRoot
            )
        }
    }

    private func finishSessionPublication(
        _ result: SessionPublicationResult,
        mode: RecordingMode,
        originalVideoURL: URL?,
        originalSessionDirectory: URL,
        exportRoot: URL
    ) {
        sessionPublishTask = nil
        menuBar.update(recording: false, elapsed: nil)

        let publishedDirectory: URL
        switch result {
        case .exported(let export, let cleanupWarning):
            if mode == .screen {
                lastFinishedVideoURL = export.videoURL ?? originalVideoURL
            }
            publishedDirectory = export.directoryURL
            FileHandle.standardError.write(
                Data("○ recording exported → \(export.directoryURL.path)\n".utf8)
            )
            if let cleanupWarning {
                FileHandle.standardError.write(
                    Data("private session cleanup failed: \(cleanupWarning)\n".utf8)
                )
            }
            postNotification(
                title: Self.readyNotificationTitle(for: mode),
                body:
                    cleanupWarning == nil
                    ? "Saved to \(exportRoot.lastPathComponent). Click to open the recording folder."
                    : "Saved to \(exportRoot.lastPathComponent), but the private working copy could not be removed.",
                directory: export.directoryURL
            )
        case .exportFailed(let message):
            if mode == .screen {
                lastFinishedVideoURL = originalVideoURL
            }
            publishedDirectory = originalSessionDirectory
            FileHandle.standardError.write(Data("recording export failed: \(message)\n".utf8))
            postNotification(
                title: Self.savedLocallyNotificationTitle(for: mode),
                body: "The export failed, but the original recording is safe.",
                directory: originalSessionDirectory
            )
        }
        setLastFinishedRecordingDirectory(publishedDirectory)
        refreshGifskiMenu()
        Task { [transcription] in await transcription.enqueue(publishedDirectory) }
        terminateIfRequested()
    }

    private func handleVideoEvent(_ event: ScreenCaptureEvent) {
        switch event {
        case .stopRequested:
            stopSession()
        case .health(let health):
            handleCaptureHealth(health)
        case .failed(let failure):
            FileHandle.standardError.write(
                Data("screen capture failed: \(failure.summary)\n".utf8)
            )
            stopSession()
        }
    }

    private func toggleVideoPause() {
        guard case .video(let session) = activeRecording,
            videoStartTask == nil,
            videoRotationTask == nil,
            videoStopTask == nil
        else { return }

        let resuming = videoPaused
        let commandDate = Date()
        if !resuming {
            ticker?.invalidate()
            ticker = nil
        }
        menuBar.updateRotatingScreenRecording(resuming: resuming)
        videoRotationTask = Task { [weak self, session] in
            let result: Result<Void, Error>
            do {
                if resuming {
                    try await session.resume(at: commandDate)
                } else {
                    try await session.pause(at: commandDate)
                }
                result = .success(())
            } catch {
                result = .failure(error)
            }
            self?.finishVideoRotation(
                result,
                session: session,
                resuming: resuming,
                commandDate: commandDate
            )
        }
    }

    private func finishVideoRotation(
        _ result: Result<Void, Error>,
        session: VideoRecordingSession,
        resuming: Bool,
        commandDate: Date
    ) {
        videoRotationTask = nil
        switch result {
        case .success:
            if resuming {
                videoPaused = false
                videoElapsedClock.resume(at: Date())
            } else {
                videoPaused = true
                videoElapsedClock.pause(at: commandDate)
            }
            if pendingVideoStop {
                stopVideoSession(session)
            } else if videoPaused {
                menuBar.updatePausedScreenRecording(
                    elapsed: Self.format(videoElapsedClock.elapsed(at: Date()))
                )
            } else {
                menuBar.update(
                    recording: true,
                    elapsed: Self.format(videoElapsedClock.elapsed(at: Date())),
                    mode: .screen
                )
                startTicker()
            }
        case .failure(let error):
            FileHandle.standardError.write(
                Data("screen capture rotation failed: \(error)\n".utf8)
            )
            pendingVideoStop = true
            stopVideoSession(session)
        }
    }

    private func handleCaptureHealth(_ event: CaptureHealthEvent) {
        menuBar.updateCaptureHealth(event)
        let line =
            "capture health: \(event.track.rawValue) \(event.code.rawValue) "
            + "\(event.severity.rawValue)\n"
        FileHandle.standardError.write(
            Data(line.utf8)
        )
    }

    private func finishVideoStartFailure(_ error: Error, session: VideoRecordingSession) {
        if case .video(let active) = activeRecording, active === session {
            activeRecording = nil
        }
        pendingVideoStop = false
        videoPaused = false
        recordingExportName = nil
        menuBar.update(recording: false, elapsed: nil)
        if Self.captureFailure(from: error)?.code == .permissionDenied {
            permissionFlow.arm(.screen)
            if !recordingPermission.presentSettingsRequired(
                for: .screenAndSystemAudio
            ) {
                permissionFlow.clear()
            }
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

    static func readyNotificationTitle(for mode: RecordingMode) -> String {
        switch mode {
        case .screen: "Screen recording ready"
        case .audioOnly: "Audio recording ready"
        }
    }

    static func savedLocallyNotificationTitle(for mode: RecordingMode) -> String {
        switch mode {
        case .screen: "Screen recording saved locally"
        case .audioOnly: "Audio recording saved locally"
        }
    }

    private func selectScreenCaptureSource(
        _ source: ScreenCaptureSourcePreference
    ) {
        guard activeRecording == nil, videoStartTask == nil else { return }
        screenCaptureSourcePreferences.selected = source
        menuBar.updateScreenCaptureSource(source)
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
            menuBar.updateTranscription(
                "transcription failed · \(name)",
                retryAvailable: true
            )
        }
    }

    private func retryTranscription() {
        menuBar.updateTranscription("retrying transcription…")
        Task { [weak self, transcription] in
            if !(await transcription.retryLastFailure()) {
                self?.menuBar.updateTranscription(nil)
            }
        }
    }

    private func selectTranscriptionEngine(_ engine: TranscriptionEngineOption) {
        TranscriptionPreferences.select(engine)
        refreshTranscriptionEngineMenu()
        if engine == .parakeet {
            presentMissingParakeetModelIfNeeded(force: true)
        }
    }

    private func toggleTranscriptRefinement() {
        TranscriptionPreferences.setRefinementEnabled(
            !Config.refineTranscriptWithAppleIntelligence()
        )
        refreshTranscriptionEngineMenu()
    }

    private func refreshTranscriptionEngineMenu() {
        if MacWhisperExecutable.installedApplicationCLI() != nil {
            try? MacWhisperExecutable.installBundledApplicationScriptIfNeeded()
        }
        let macWhisperAvailable =
            MacWhisperExecutable.resolve(
                configuredPath: Config.transcriptionExecutable()
            ) != nil
        var engine = Config.transcriptionSelection().engine
        if engine == .macwhisper, !macWhisperAvailable {
            TranscriptionPreferences.select(.parakeet)
            engine = .parakeet
        }
        let parakeetModel =
            (try? ParakeetModelID(
                configurationValue: TranscriptionPreferences.defaultParakeetModel
            )) ?? .v3
        menuBar.updateTranscriptionEngine(
            engine,
            macWhisperAvailable: macWhisperAvailable,
            parakeetModelAvailable: ParakeetModelInstaller.isInstalled(parakeetModel)
        )
        let refinementCapability = OnDeviceTranscriptRefinementAdviser.currentCapability(
            language: Config.transcriptionLanguage()
        )
        menuBar.updateTranscriptRefinement(
            enabled: Config.refineTranscriptWithAppleIntelligence(),
            available: refinementCapability.canEnable,
            detail: refinementCapability.detail
        )
    }

    private func presentMissingParakeetModelIfNeeded(force: Bool = false) {
        guard Config.transcriptionEnabled() else { return }
        let selection = Config.transcriptionSelection()
        guard selection.engine == .parakeet,
            let model = try? ParakeetModelID(configurationValue: selection.model),
            !ParakeetModelInstaller.isInstalled(model)
        else { return }
        guard force || !presentedMissingModelPrompt else { return }
        presentedMissingModelPrompt = true
        presentParakeetModelSetup()
    }

    private func presentParakeetModelSetup() {
        let alert = NSAlert()
        alert.messageText = "Set Up Local Parakeet Transcription"
        alert.informativeText =
            "Record needs the Parakeet v3 model (about 460 MB) for on-device transcription. "
            + "Download the pinned model from FluidInference, then import its folder. "
            + "Recording continues to work without the model."
        alert.addButton(withTitle: "Open Verified Download Guide")
        alert.addButton(withTitle: "Import Downloaded Model…")
        alert.addButton(withTitle: "Later")
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            NSWorkspace.shared.open(ParakeetModelInstaller.downloadGuide)
        case .alertSecondButtonReturn:
            chooseAndImportParakeetModel()
        default:
            break
        }
    }

    private func chooseAndImportParakeetModel() {
        guard !modelImportInProgress else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose the Downloaded Parakeet v3 Model Folder"
        panel.prompt = "Import Model"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let source = panel.url else { return }

        modelImportInProgress = true
        let accessed = source.startAccessingSecurityScopedResource()
        menuBar.updateTranscription("verifying Parakeet model…")
        Task { [weak self, transcription, root] in
            let result = await Task.detached(priority: .userInitiated) {
                Result { try ParakeetModelInstaller.installV3(from: source) }
            }.value
            if accessed { source.stopAccessingSecurityScopedResource() }
            guard let self else { return }
            self.modelImportInProgress = false
            self.menuBar.updateTranscription(nil)
            switch result {
            case .success:
                self.refreshTranscriptionEngineMenu()
                let alert = NSAlert()
                alert.messageText = "Parakeet Is Ready"
                alert.informativeText =
                    "The verified model was installed locally. Pending recordings will now be transcribed."
                alert.addButton(withTitle: "OK")
                NSApp.activate(ignoringOtherApps: true)
                alert.runModal()
                await transcription.resumePending(root: root)
            case .failure(let error):
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = "Record Couldn’t Import This Model"
                alert.informativeText =
                    String(describing: error)
                    + " Download it again from the verified source and retry."
                alert.addButton(withTitle: "Open Verified Source")
                alert.addButton(withTitle: "Cancel")
                NSApp.activate(ignoringOtherApps: true)
                if alert.runModal() == .alertFirstButtonReturn {
                    NSWorkspace.shared.open(ParakeetModelInstaller.verifiedSource)
                }
            }
        }
    }

    private func tick() {
        guard let activeRecording else { return }
        let elapsed: TimeInterval
        switch activeRecording {
        case .audio(let session):
            elapsed = Date().timeIntervalSince(session.startedAt)
        case .video:
            elapsed = videoElapsedClock.elapsed(at: Date())
        }
        menuBar.update(
            recording: true,
            elapsed: Self.format(elapsed),
            mode: activeRecording.mode
        )
    }

    private func openFolder() {
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        NSWorkspace.shared.open(root)
    }

    private func openLastRecording() {
        guard
            let directory = lastFinishedRecordingDirectory,
            RecentRecordingLocator.isFinishedSession(
                directory,
                under: recentRecordingRoots
            )
        else {
            setLastFinishedRecordingDirectory(nil)
            refreshRecentRecordingMenu()
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([directory])
    }

    private var recentRecordingRoots: [URL] {
        [exportDirectoryLease?.url, root].compactMap { $0 }
    }

    private func setLastFinishedRecordingDirectory(_ directory: URL?) {
        let directory = directory?.standardizedFileURL
        let validated = directory.flatMap {
            RecentRecordingLocator.isFinishedSession($0, under: recentRecordingRoots)
                ? $0
                : nil
        }
        lastFinishedRecordingDirectory = validated
        menuBar.updateLastRecording(available: validated != nil)
    }

    private func refreshRecentRecordingMenu() {
        recentRecordingRefreshTask?.cancel()
        let roots = recentRecordingRoots
        recentRecordingRefreshTask = Task { [weak self] in
            let snapshot = await Task.detached(priority: .utility) {
                RecentRecordingLocator.snapshot(under: roots)
            }.value
            guard !Task.isCancelled else { return }
            self?.setLastFinishedRecordingDirectory(snapshot.recordingDirectory)
            self?.lastFinishedVideoURL = snapshot.videoURL
            self?.refreshGifskiMenu()
            self?.recentRecordingRefreshTask = nil
        }
    }

    private func checkForUpdates() {
        NSApp.activate(ignoringOtherApps: true)
        updateController.checkForUpdates()
    }

    private func toggleLaunchAtLogin() {
        let previousState = launchAtLoginController.state
        do {
            let state = try launchAtLoginController.toggle()
            refreshLaunchAtLoginMenu()
            if state == .requiresApproval, previousState != .requiresApproval {
                presentLaunchAtLoginApproval()
            }
        } catch {
            refreshLaunchAtLoginMenu()
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Record couldn’t change Login Items"
            alert.informativeText =
                error.localizedDescription
                + "\n\nYou can manage Record manually in System Settings → General → Login Items."
            alert.addButton(withTitle: "Open Login Items")
            alert.addButton(withTitle: "Cancel")
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn {
                launchAtLoginController.openSystemSettings()
            }
        }
    }

    private func refreshLaunchAtLoginMenu() {
        menuBar.updateLaunchAtLogin(launchAtLoginController.state)
    }

    private func presentLaunchAtLoginApproval() {
        let alert = NSAlert()
        alert.messageText = "Approve Record at Login"
        alert.informativeText =
            "macOS needs your approval before Record can open automatically after sign-in."
        alert.addButton(withTitle: "Open Login Items")
        alert.addButton(withTitle: "Later")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            launchAtLoginController.openSystemSettings()
        }
    }

    func handleTerminationRequest(
        appleEvent: NSAppleEventDescriptor?
    ) -> Bool {
        guard let pendingRecordingMode = permissionFlow.pendingMode else { return false }
        guard Self.isPrivacySettingsQuitEvent(appleEvent) else { return false }

        restart(resuming: pendingRecordingMode)
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

    private func restart(resuming mode: RecordingMode) {
        guard activeRecording == nil else { return }
        permissionFlow.clear()
        permissionTask?.cancel()
        permissionTask = nil
        pendingRecordingIntentStore.save(mode)

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
                self?.pendingRecordingIntentStore.clear()
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
        if candidate.deletingLastPathComponent() == root.standardizedFileURL {
            return candidate
        }
        if let exportRoot = exportDirectoryLease?.url.standardizedFileURL,
            candidate.deletingLastPathComponent() == exportRoot
        {
            return candidate
        }
        return root
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
        notifications.updateExportRoot(exportDirectoryLease?.url)
        menuBar.updateExportDirectory(
            exportDirectoryLease?.url ?? exportDirectoryAccess.suggestedDirectory
        )
    }

    private func ensureExportFolderAccess() {
        guard exportDirectoryLease == nil else { return }
        NSApp.activate(ignoringOtherApps: true)
        chooseExportFolder()
    }

    private func chooseExportFolder() {
        do {
            guard let selection = try exportDirectoryAccess.choose() else { return }
            exportDirectoryLease = selection
            notifications.updateExportRoot(selection.url)
            menuBar.updateExportDirectory(selection.url)
            refreshRecentRecordingMenu()
            Task { [transcription] in
                await transcription.resumePending(
                    root: selection.url,
                    recoverInterrupted: false
                )
            }
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
