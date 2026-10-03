import Darwin
import Foundation
import RecordCore

struct PendingTranscription: Sendable {
    let directory: URL
    let directoryLease: ExportDirectoryLease?

    static func sameDirectory(_ lhs: URL?, _ rhs: URL) -> Bool {
        lhs?.resolvingSymlinksInPath().path == rhs.resolvingSymlinksInPath().path
    }

    init(directory: URL, retaining directoryLease: ExportDirectoryLease? = nil) {
        self.directory = directory.standardizedFileURL
        self.directoryLease = directoryLease
    }
}

struct TranscriptionRetryState: Sendable {
    private var failedJob: PendingTranscription?
    var failedDirectory: URL? { failedJob?.directory }

    mutating func recordFailure(
        in directory: URL, retaining directoryLease: ExportDirectoryLease? = nil
    ) {
        failedJob = PendingTranscription(directory: directory, retaining: directoryLease)
    }

    mutating func clear() { failedJob = nil }

    mutating func takeFailure() -> PendingTranscription? {
        defer { clear() }
        return failedJob
    }
}

struct TranscriptRefinementPass: Equatable, Sendable {
    let result: TranscriptRefinementResult
    let outcome: TranscriptRefinementAdviserOutcome
}

/// Post-recording pipeline: a serial queue of session folders to transcribe.
/// mic.wav → "me", system.wav → "them"; each track's segments are shifted by
/// its start offset, merged by timestamp, and written as transcript.json
/// (canonical) plus transcript.md (readable). The filesystem is the queue —
/// `resumePending()` rescans at launch, so a crash or quit mid-transcription
/// just retries on next run. Failures append to the session's transcribe.log
/// and never block later jobs.
actor TranscriptionCoordinator {
    enum Status: Sendable {
        case idle
        case transcribing(session: String, queued: Int)
        case failed(session: String)
        case progress(session: String, stage: String, queued: Int)
        case deferred(session: String)
    }

    private var queue: [PendingTranscription] = []
    private var draining = false
    private var activeJob: PendingTranscription?
    private var activeTask: Task<Void, Error>?
    private var engine: TranscriptionEngine?
    private var engineSelection: TranscriptionSelection?
    private var retryState = TranscriptionRetryState()
    private var statusHandler: (@Sendable (Status) -> Void)?
    private let notificationHandler: @Sendable (RecordNotification) -> Void
    private let refinementAdviser: any TranscriptRefinementAdvising
    private let engineFactory: @Sendable (TranscriptionSelection) throws -> any TranscriptionEngine
    private let refinementEnabled: @Sendable () -> Bool
    private let transcriptionEnabled: @Sendable () -> Bool

    init(
        notificationHandler: @escaping @Sendable (RecordNotification) -> Void = { _ in },
        refinementAdviser: any TranscriptRefinementAdvising =
            OnDeviceTranscriptRefinementAdviser(),
        engineFactory:
            @escaping @Sendable (TranscriptionSelection) throws -> any TranscriptionEngine =
            TranscriptionCoordinator.makeEngine,
        refinementEnabled: @escaping @Sendable () -> Bool = Config
            .refineTranscriptWithAppleIntelligence,
        transcriptionEnabled: @escaping @Sendable () -> Bool = Config.transcriptionEnabled
    ) {
        self.notificationHandler = notificationHandler
        self.refinementAdviser = refinementAdviser
        self.engineFactory = engineFactory
        self.refinementEnabled = refinementEnabled
        self.transcriptionEnabled = transcriptionEnabled
    }

    func setStatusHandler(_ handler: @escaping @Sendable (Status) -> Void) {
        statusHandler = handler
    }

    /// Queue a finished session. With transcription disabled in config, the
    /// completion hook still fires — it just gets an untranscribed folder.
    func enqueue(_ sessionDir: URL, retaining directoryLease: ExportDirectoryLease? = nil) {
        guard transcriptionEnabled() else {
            runHook(for: sessionDir)
            return
        }
        appendIfNeeded(sessionDir, retaining: directoryLease)
        drainIfIdle()
    }

    /// Retry the most recent failed job without requiring an app restart or
    /// touching the recording. Returns false when there is nothing to retry.
    @discardableResult
    func retryLastFailure() -> Bool {
        guard transcriptionEnabled(), let failedJob = retryState.takeFailure()
        else { return false }
        appendIfNeeded(failedJob.directory, retaining: failedJob.directoryLease)
        drainIfIdle()
        return true
    }

    /// Explicit retry also works for a partial or deferred session after relaunch.
    func retry(_ directory: URL, retaining lease: ExportDirectoryLease? = nil) {
        guard transcriptionEnabled(),
            !PendingTranscription.sameDirectory(activeJob?.directory, directory)
        else { return }
        if var checkpoint = try? TranscriptionCheckpoint.read(from: directory) {
            checkpoint.state = .pending
            do { try checkpoint.write(to: directory) } catch {
                log(directory, "could not resume transcription: \(error)"); return
            }
        }
        appendIfNeeded(directory, retaining: lease)
        drainIfIdle()
    }

    func deferSession(_ directory: URL) throws {
        let directory = directory.standardizedFileURL
        // Persist before removing queued work, so a quit cannot restart it.
        var checkpoint =
            (try? TranscriptionCheckpoint.read(from: directory))
            ?? TranscriptionCheckpoint(engine: "", model: "", language: "", tracks: [])
        checkpoint.state = .deferred
        try checkpoint.write(to: directory)
        queue.removeAll { PendingTranscription.sameDirectory($0.directory, directory) }
        if PendingTranscription.sameDirectory(activeJob?.directory, directory) {
            activeTask?.cancel()
        }
        publish(.deferred(session: directory.lastPathComponent))
    }

    /// Scan the recordings root for finalized sessions that were never
    /// transcribed. Legacy Quill `meta.json` sessions remain readable.
    func resumePending(
        root: URL, recoverInterrupted: Bool = true,
        retaining directoryLease: ExportDirectoryLease? = nil
    ) {
        if recoverInterrupted {
            let recovery = SessionRecovery.recover(
                in: root,
                inspectMedia: SessionMediaInspector.inspect,
                recoverPartialMedia: true
            )
            if let notification = Self.recoveryNotification(for: recovery, root: root) {
                notificationHandler(notification)
            }
            if !recovery.interrupted.isEmpty || !recovery.failed.isEmpty
                || !recovery.promotedMedia.isEmpty || !recovery.quarantinedMedia.isEmpty
            {
                let interruptedCount = recovery.interrupted.count
                let failedCount = recovery.failed.count
                let message =
                    "recovered \(interruptedCount) interrupted and marked "
                    + "\(failedCount) empty session(s) failed; promoted "
                    + "\(recovery.promotedMedia.count), quarantined "
                    + "\(recovery.quarantinedMedia.count) media artifact(s)\n"
                FileHandle.standardError.write(Data(message.utf8))
            }
            for failure in recovery.errors {
                let directory = failure.directory.lastPathComponent
                let message =
                    "warning: could not recover \(directory): \(failure.description)\n"
                FileHandle.standardError.write(Data(message.utf8))
            }
        }
        guard transcriptionEnabled() else { return }
        let pending = Self.pendingSessionDirectories(root: root)
        for dir in pending {
            appendIfNeeded(dir, retaining: directoryLease)
        }
        if !pending.isEmpty {
            FileHandle.standardError.write(
                Data(
                    "resuming \(pending.count) untranscribed session(s)\n".utf8
                ))
        }
        drainIfIdle()
    }

    static func pendingSessionDirectories(
        root: URL,
        fileManager: FileManager = .default
    ) -> [URL] {
        guard
            let entries = try? fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: nil
            )
        else { return [] }

        return entries.filter { directory in
            guard
                let values = try? directory.resourceValues(forKeys: [
                    .isDirectoryKey, .isSymbolicLinkKey,
                ]),
                values.isDirectory == true, values.isSymbolicLink != true,
                directory.resolvingSymlinksInPath().deletingLastPathComponent()
                    == root.resolvingSymlinksInPath()
            else { return false }
            guard SessionMeta.isFinalized(directory) else { return false }
            if let checkpoint = try? TranscriptionCheckpoint.read(from: directory) {
                guard checkpoint.state != .deferred, checkpoint.state != .complete else {
                    return false
                }
            } else if fileManager.fileExists(
                atPath: directory.appendingPathComponent("transcript.json").path)
            {
                return false
            }
            guard let metadata = try? SessionMeta.read(from: directory) else { return false }
            return !metadata.tracks.isEmpty
        }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static func recoveryNotification(
        for report: SessionRecovery.Report,
        root: URL
    ) -> RecordNotification? {
        let interrupted = report.interrupted.count
        let failed = report.failed.count
        let errors = report.errors.count
        let promoted = report.promotedMedia.count
        let quarantined = report.quarantinedMedia.count
        guard interrupted + failed + promoted + quarantined + errors > 0 else { return nil }

        var details: [String] = []
        if interrupted > 0 {
            details.append(
                "preserved \(interrupted) interrupted recording\(interrupted == 1 ? "" : "s")"
            )
        }
        if failed > 0 {
            details.append(
                "marked \(failed) empty session\(failed == 1 ? "" : "s") as failed"
            )
        }
        if promoted > 0 {
            details.append(
                "restored \(promoted) playable media file\(promoted == 1 ? "" : "s")"
            )
        }
        if quarantined > 0 {
            details.append(
                "quarantined \(quarantined) partial file\(quarantined == 1 ? "" : "s")"
            )
        }
        if errors > 0 {
            details.append(
                "found \(errors) session\(errors == 1 ? "" : "s") needing manual review"
            )
        }

        return RecordNotification(
            title: "Recording recovery finished",
            body: "Record \(details.joined(separator: ", ")). Click to open temp sessions.",
            destinationDirectory: root
        )
    }

    // MARK: -

    private func drainIfIdle() {
        guard !draining, !queue.isEmpty else { return }
        draining = true
        retryState.clear()
        Task { await drain() }
    }

    private func appendIfNeeded(
        _ directory: URL, retaining directoryLease: ExportDirectoryLease? = nil
    ) {
        let directory = directory.standardizedFileURL
        guard !PendingTranscription.sameDirectory(activeJob?.directory, directory),
            !queue.contains(where: { PendingTranscription.sameDirectory($0.directory, directory) })
        else { return }
        queue.append(PendingTranscription(directory: directory, retaining: directoryLease))
    }

    private func drain() async {
        while !queue.isEmpty {
            let job = queue.removeFirst()
            let dir = job.directory
            // A new export preference must not revoke access while this job
            // awaits speech processing, writes its result, or records failure.
            defer { withExtendedLifetime(job.directoryLease) {} }
            publish(.transcribing(session: dir.lastPathComponent, queued: queue.count))
            activeJob = job
            let task = Task { try await self.transcribe(dir) }
            activeTask = task
            do {
                try await task.value
                notificationHandler(
                    RecordNotification(
                        title: "Transcript ready",
                        body: "Transcription finished. Click to open the recording folder.",
                        destinationDirectory: dir
                    )
                )
                runHook(for: dir)
            } catch  where task.isCancelled || error is CancellationError {
                if var checkpoint = try? TranscriptionCheckpoint.read(from: dir) {
                    checkpoint.state = .deferred
                    try? checkpoint.write(to: dir)
                }
                publish(.deferred(session: dir.lastPathComponent))
            } catch {
                log(dir, "transcription failed: \(error)")
                retryState.recordFailure(in: dir, retaining: job.directoryLease)
                notificationHandler(
                    RecordNotification(
                        title: "Transcription couldn’t finish",
                        body:
                            "The recording is safe. Click to open its folder and review transcribe.log.",
                        destinationDirectory: dir
                    )
                )
            }
            activeJob = nil
            activeTask = nil
        }
        await engine?.release()
        engine = nil
        engineSelection = nil
        publish(
            retryState.failedDirectory.map { .failed(session: $0.lastPathComponent) }
                ?? .idle
        )
        draining = false
        // An enqueue that landed between the loop exiting and the release
        // finishing would otherwise sit until the next enqueue.
        drainIfIdle()
    }

    func transcribe(_ dir: URL) async throws {
        let meta = try SessionMeta.read(from: dir)
        publish(
            .progress(
                session: dir.lastPathComponent, stage: "Loading transcription engine",
                queued: queue.count))
        let engine = try await preparedEngine()

        let selection = Config.transcriptionSelection()
        let previous = try? TranscriptionCheckpoint.read(from: dir)
        var checkpoint = TranscriptionCheckpoint(
            engine: engine.name, model: engine.model, language: selection.language,
            state: .processing,
            tracks: meta.tracks.map { track in
                let audio = dir.appendingPathComponent(track.file)
                let source = TranscriptionCheckpoint.Source(
                    filename: track.file, speaker: track.speaker,
                    offsetMilliseconds: track.offsetMs,
                    byteCount: LocalFilePolicy.regularFileSize(at: audio) ?? 0,
                    modifiedAt: (try? audio.resourceValues(forKeys: [.contentModificationDateKey]))?
                        .contentModificationDate ?? .distantPast)
                return .init(
                    source: source,
                    segments: previous?.cachedSegments(
                        for: source, engine: engine.name, model: engine.model,
                        language: selection.language))
            })
        try Task.checkCancellation()
        try checkpoint.write(to: dir)
        for index in checkpoint.tracks.indices where checkpoint.tracks[index].segments == nil {
            try Task.checkCancellation()
            let source = checkpoint.tracks[index].source
            let audio = dir.appendingPathComponent(source.filename)
            publish(
                .progress(
                    session: dir.lastPathComponent,
                    stage:
                        "\(source.speaker == "me" ? "Microphone" : "System audio") · \(checkpoint.completedTracks)/\(checkpoint.tracks.count) complete",
                    queued: queue.count))
            do {
                guard LocalFilePolicy.isNonemptyRegularFile(audio),
                    audio.resolvingSymlinksInPath().deletingLastPathComponent()
                        == dir.resolvingSymlinksInPath()
                else { throw PipelineError.unreadableTrack }
                let segments = try await engine.transcribe(audio) { [weak self] fraction in
                    await self?.trackProgress(fraction, speaker: source.speaker, directory: dir)
                }
                checkpoint.tracks[index].segments = segments.map {
                    TranscriptDocument.Segment(
                        speaker: source.speaker,
                        startMilliseconds: Int($0.start * 1000) + source.offsetMilliseconds,
                        endMilliseconds: Int($0.end * 1000) + source.offsetMilliseconds,
                        text: $0.text)
                }
                // Persist deferral together with a late successful track, so a
                // crash cannot accidentally re-enable a cancelled job.
                if Task.isCancelled { checkpoint.state = .deferred }
                try checkpoint.write(to: dir)
            } catch is CancellationError { throw CancellationError() } catch {
                log(dir, "track \(source.filename) failed: \(error)")
            }
        }
        try Task.checkCancellation()
        checkpoint.state = .needsRetry
        try checkpoint.write(to: dir)
        try Self.validateTrackResults(
            attempted: checkpoint.tracks.count, succeeded: checkpoint.completedTracks)
        var merged = checkpoint.tracks.flatMap { $0.segments ?? [] }
        merged.sort { $0.startMilliseconds < $1.startMilliseconds }

        let rawTranscript = TranscriptDocument(
            engine: engine.name,
            model: engine.model,
            createdAt: ISO8601DateFormatter().string(from: Date()),
            segments: merged,
            incompleteTrackCount: checkpoint.isPartial
                ? checkpoint.tracks.count - checkpoint.completedTracks : nil
        )
        let suppression =
            Config.suppressSpeakerEcho()
            ? TranscriptEchoSuppressor.suppress(merged)
            : TranscriptEchoSuppressionResult(
                segments: merged,
                suppressedMicrophoneSegments: []
            )
        let rawTranscriptURL = dir.appendingPathComponent("transcript.raw.json")
        let refinementReportURL = dir.appendingPathComponent("transcript.refinement.json")
        // Always preserve raw recognition before attempting optional cleanup.
        try rawTranscript.writeJSON(to: rawTranscriptURL)

        var finalSegments = suppression.segments
        publish(
            .progress(
                session: dir.lastPathComponent, stage: "Preparing transcript", queued: queue.count))
        if refinementEnabled() {
            publish(
                .progress(
                    session: dir.lastPathComponent, stage: "Cleaning transcript",
                    queued: queue.count))
            let sourceTranscript = TranscriptDocument(
                engine: rawTranscript.engine,
                model: rawTranscript.model,
                createdAt: rawTranscript.createdAt,
                segments: suppression.segments
            )
            let refinementPass = await Self.refinementPass(
                source: sourceTranscript,
                language: Config.transcriptionLanguage(),
                adviser: refinementAdviser
            )
            let report = try TranscriptRefinementReport(
                source: rawTranscript,
                adviserOutcome: refinementPass.outcome,
                result: refinementPass.result
            )
            try report.write(to: dir)
            finalSegments = refinementPass.result.segments
            log(
                dir,
                "transcript refinement \(refinementPass.outcome.rawValue); removed "
                    + "\(refinementPass.result.removals.count) candidate(s), marked "
                    + "\(refinementPass.result.overlaps.count) overlap group(s)"
            )
        }

        if !suppression.suppressedMicrophoneSegments.isEmpty {
            log(
                dir,
                "speaker echo suppression removed "
                    + "\(suppression.suppressedMicrophoneSegments.count) mic segment(s); "
                    + "unsuppressed segments are in transcript.raw.json"
            )
        }
        let transcript = TranscriptDocument(
            engine: rawTranscript.engine,
            model: rawTranscript.model,
            createdAt: rawTranscript.createdAt,
            segments: finalSegments,
            incompleteTrackCount: rawTranscript.incompleteTrackCount
        )
        try Task.checkCancellation()
        publish(
            .progress(
                session: dir.lastPathComponent, stage: "Saving transcript", queued: queue.count))
        try transcript.write(to: dir, title: dir.lastPathComponent)
        if !refinementEnabled() {
            try? FileManager.default.removeItem(at: refinementReportURL)
        }
        if checkpoint.completedTracks < checkpoint.tracks.count {
            throw PipelineError.partialTracksFailed(
                checkpoint.tracks.count - checkpoint.completedTracks)
        }
        checkpoint.state = .complete
        try checkpoint.write(to: dir)
        log(dir, "done — \(finalSegments.count) segments")
    }

    private func trackProgress(_ fraction: Double, speaker: String, directory: URL) {
        guard fraction.isFinite, !Task.isCancelled, activeTask?.isCancelled != true else { return }
        let percent = Int(min(1, max(0, fraction)) * 100)
        publish(
            .progress(
                session: directory.lastPathComponent,
                stage: "\(speaker == "me" ? "Microphone" : "System audio") · \(percent)%",
                queued: queue.count))
    }

    static func validateTrackResults(attempted: Int, succeeded: Int) throws {
        guard attempted == 0 || succeeded > 0 else {
            throw PipelineError.allTracksFailed(attempted)
        }
    }

    static func refinementPass(
        source: TranscriptDocument,
        language: String,
        adviser: any TranscriptRefinementAdvising
    ) async -> TranscriptRefinementPass {
        let plan = TranscriptRefiner.plan(for: source.segments)
        let advice = await adviser.advise(
            candidates: plan.candidates,
            language: language
        )
        return TranscriptRefinementPass(
            result: TranscriptRefiner.apply(advice.decisions, to: plan),
            outcome: advice.outcome
        )
    }

    private func preparedEngine() async throws -> TranscriptionEngine {
        let selection = Config.transcriptionSelection()
        if let engine, engineSelection == selection { return engine }
        await engine?.release()
        engine = nil
        engineSelection = nil

        let newEngine = try engineFactory(selection)
        try await newEngine.prepare()
        engine = newEngine
        engineSelection = selection
        return newEngine
    }

    private static func makeEngine(_ selection: TranscriptionSelection) throws
        -> any TranscriptionEngine
    {
        let newEngine: TranscriptionEngine
        switch selection.engine {
        case .parakeet:
            let model = try ParakeetModelID(configurationValue: selection.model)
            newEngine = ParakeetEngine(selection: model)
        case .macwhisper:
            guard
                let executable = MacWhisperExecutable.resolve(
                    configuredPath: selection.executable
                )
            else {
                throw MacWhisperEngine.EngineError.executableMissing(
                    URL(fileURLWithPath: selection.executable ?? "mw")
                )
            }
            newEngine = try MacWhisperEngine(
                executable: executable,
                model: selection.model,
                language: selection.language
            )
        }
        return newEngine
    }

    /// Runs the configured executable directly without invoking a shell.
    /// `{session}` arguments expand to the completed session directory.
    private func runHook(for dir: URL) {
        guard let hook = Config.completionHook() else { return }
        guard FileManager.default.isExecutableFile(atPath: hook.executable) else {
            log(dir, "completion hook is not executable: \(hook.executable)")
            return
        }
        guard Self.claimCompletionHook(in: dir) else {
            log(dir, "completion hook already claimed; skipping duplicate launch")
            return
        }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: hook.executable)
        task.arguments = hook.arguments.map {
            $0.replacingOccurrences(of: "{session}", with: dir.path)
        }
        do {
            try task.run()
        } catch {
            log(dir, "completion hook failed to launch: \(error)")
        }
    }

    /// Claims the hook before process launch. A crash after this atomic file
    /// creation may omit a hook, but can never execute it twice after restart.
    static func claimCompletionHook(in directory: URL) -> Bool {
        let marker = directory.appendingPathComponent(".record-completion-hook.started")
        return marker.withUnsafeFileSystemRepresentation { path in
            guard let path else { return false }
            let descriptor = Darwin.open(
                path,
                O_WRONLY | O_CREAT | O_EXCL,
                mode_t(S_IRUSR | S_IWUSR)
            )
            guard descriptor >= 0 else { return false }
            Darwin.close(descriptor)
            return true
        }
    }

    private func log(_ dir: URL, _ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        let url = dir.appendingPathComponent("transcribe.log")
        if let handle = FileHandle(forWritingAtPath: url.path) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: url)
        }
    }

    private func publish(_ status: Status) {
        statusHandler?(status)
    }
}

enum PipelineError: Error, CustomStringConvertible, Equatable {
    case allTracksFailed(Int)
    case partialTracksFailed(Int)
    case unreadableTrack

    var description: String {
        switch self {
        case .unreadableTrack: return "audio source is missing or unsafe"
        case .partialTracksFailed(let count):
            return "partial transcript saved; \(count) track(s) need retry"
        case .allTracksFailed(let count):
            return "all \(count) available audio tracks failed transcription"
        }
    }
}

/// The slice of session metadata the coordinator needs: which files exist,
/// who they represent, and their offsets from the earliest track.
private struct SessionMeta {
    struct Track {
        let file: String
        let speaker: String
        let offsetMs: Int
    }

    let tracks: [Track]

    enum MetaError: Error, CustomStringConvertible {
        case unreadable(URL)
        case unsafeTrackFilename(String)

        var description: String {
            switch self {
            case .unreadable(let url): return "can't parse \(url.path)"
            case .unsafeTrackFilename(let filename):
                return "unsafe track filename in legacy session: \(filename)"
            }
        }
    }

    static func read(from dir: URL) throws -> SessionMeta {
        guard let values = try? dir.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
            values.isDirectory == true, values.isSymbolicLink != true
        else { throw MetaError.unreadable(dir) }
        if LocalFilePolicy.isNonemptyRegularFile(dir.appendingPathComponent("session.json")),
            let manifest = try? SessionManifest.read(from: dir)
        {
            guard manifest.state == .finalized || manifest.state == .interrupted else {
                throw MetaError.unreadable(dir.appendingPathComponent("session.json"))
            }
            let tracks = manifest.tracks.compactMap { track -> Track? in
                switch track.kind {
                case .microphone:
                    return Track(
                        file: track.filename,
                        speaker: track.speaker
                            ?? SessionMediaLayout.defaultSpeaker(for: .microphone)!,
                        offsetMs: track.startOffsetMilliseconds
                    )
                case .systemAudio:
                    return Track(
                        file: track.filename,
                        speaker: track.speaker
                            ?? SessionMediaLayout.defaultSpeaker(for: .systemAudio)!,
                        offsetMs: track.startOffsetMilliseconds
                    )
                case .screen, .camera:
                    return nil
                }
            }
            return SessionMeta(tracks: tracks)
        }

        let url = dir.appendingPathComponent("meta.json")
        guard
            let size = LocalFilePolicy.regularFileSize(at: url), size <= 1_048_576,
            let data = try? Data(contentsOf: url),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let files = json["files"] as? [String: String]
        else { throw MetaError.unreadable(url) }

        // Sessions recorded before offsets were captured default to 0 —
        // tracks start within tens of milliseconds of each other anyway.
        let offsets = json["start_offset_ms"] as? [String: Int] ?? [:]
        var tracks: [Track] = []
        if let mic = files["mic"] {
            guard SessionPathPolicy.isSafeRelativeFilename(mic) else {
                throw MetaError.unsafeTrackFilename(mic)
            }
            tracks.append(
                Track(
                    file: mic,
                    speaker: SessionMediaLayout.defaultSpeaker(for: .microphone)!,
                    offsetMs: offsets["mic"] ?? 0
                )
            )
        }
        if let system = files["system"] {
            guard SessionPathPolicy.isSafeRelativeFilename(system) else {
                throw MetaError.unsafeTrackFilename(system)
            }
            tracks.append(
                Track(
                    file: system,
                    speaker: SessionMediaLayout.defaultSpeaker(for: .systemAudio)!,
                    offsetMs: offsets["system"] ?? 0
                )
            )
        }
        return SessionMeta(tracks: tracks)
    }

    static func isFinalized(_ dir: URL) -> Bool {
        if LocalFilePolicy.isNonemptyRegularFile(dir.appendingPathComponent("session.json")),
            let manifest = try? SessionManifest.read(from: dir)
        {
            return manifest.state == .finalized || manifest.state == .interrupted
        }
        return FileManager.default.fileExists(
            atPath: dir.appendingPathComponent("meta.json").path
        )
    }
}
