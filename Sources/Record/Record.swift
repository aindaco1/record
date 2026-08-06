import AppKit
import ArgumentParser
import Foundation
import RecordCapture
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
        app.run()
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
    private let transcription = TranscriptionCoordinator()
    private let exportDirectoryAccess = ExportDirectoryAccess()
    private var exportDirectoryLease: ExportDirectoryLease?
    private var activeRecording: ActiveRecording?
    private var ticker: Timer?
    private var videoStartTask: Task<Void, Never>?
    private var videoStopTask: Task<Void, Never>?
    private var pendingVideoStop = false
    private var quitAfterStop = false

    init(root: URL) {
        self.root = root
        menuBar.onToggle = { [weak self] in self?.toggle() }
        menuBar.onStartAudioOnly = { [weak self] in self?.startAudioSession() }
        menuBar.onSelectTranscriptionEngine = { [weak self] in
            self?.selectTranscriptionEngine($0)
        }
        menuBar.onOpenFolder = { [weak self] in self?.openFolder() }
        menuBar.onChooseExportFolder = { [weak self] in self?.chooseExportFolder() }
        menuBar.onQuit = { [weak self] in self?.shutdown() }
        menuBar.update(recording: false, elapsed: nil)
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
            notifyUser(title: "Record — recording failed", body: "\(error)")
            return
        }

        menuBar.update(recording: true, elapsed: "0:00", mode: .audioOnly)
        startTicker()
    }

    private func startVideoSession() {
        guard activeRecording == nil else { return }
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

        activeRecording = .video(newSession)
        pendingVideoStop = false
        menuBar.updatePreparingScreenRecording()
        videoStartTask = Task { [weak self, newSession] in
            do {
                let configuration = try VideoCaptureProfile.mainDisplayConfiguration()
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
            notifyUser(
                title: "Record — finalization failed",
                body: "The media was preserved, but session recovery is required."
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
        if case .video(let active) = activeRecording, active === session {
            activeRecording = nil
        }
        menuBar.update(recording: false, elapsed: nil)

        switch result {
        case .success(let outcome):
            logIngress(outcome.ingress)
            if outcome.state == .finalized, let mediaURL = outcome.mediaURL {
                publishVideo(mediaURL, startedAt: session.startedAt)
            } else {
                notifyUser(
                    title: "Record — video preserved",
                    body:
                        "Capture ended with an error; inspect \(outcome.sessionDirectory.lastPathComponent)."
                )
            }
        case .failure(let error):
            FileHandle.standardError.write(Data("video finalization failed: \(error)\n".utf8))
            notifyUser(
                title: "Record — video finalization failed",
                body: "Recoverable media remains in session storage."
            )
        }
        terminateIfRequested()
    }

    private func publishVideo(_ mediaURL: URL, startedAt: Date) {
        guard let exportDirectoryLease else {
            notifyUser(
                title: "Record — video ready",
                body: "Saved in session storage. Choose an export folder for automatic copies."
            )
            return
        }
        do {
            let exportedURL = try FinishedVideoExporter.export(
                sourceURL: mediaURL,
                to: exportDirectoryLease.url,
                startedAt: startedAt
            )
            FileHandle.standardError.write(Data("○ video exported → \(exportedURL.path)\n".utf8))
            notifyUser(
                title: "Record — video ready",
                body: "Saved to \(exportedURL.deletingLastPathComponent().lastPathComponent)."
            )
        } catch {
            FileHandle.standardError.write(Data("video export failed: \(error)\n".utf8))
            notifyUser(
                title: "Record — export failed",
                body: "The original video remains in session storage."
            )
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
        menuBar.update(recording: false, elapsed: nil)
        reportRecordingStartFailure(error)
        terminateIfRequested()
    }

    private func reportRecordingStartFailure(_ error: Error) {
        FileHandle.standardError.write(Data("recording start failed: \(error)\n".utf8))
        notifyUser(title: "Record — recording failed", body: "\(error)")
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
            notifyUser(
                title: "Record — export folder unavailable",
                body: "Choose the folder again to restore access."
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
