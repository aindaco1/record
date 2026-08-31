import Darwin
import Foundation
import RecordCore

struct TranscriptionRetryState: Equatable, Sendable {
    private(set) var failedDirectory: URL?

    mutating func recordFailure(in directory: URL) {
        failedDirectory = directory.standardizedFileURL
    }

    mutating func clear() {
        failedDirectory = nil
    }

    mutating func takeFailure() -> URL? {
        defer { failedDirectory = nil }
        return failedDirectory
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
    }

    private var queue: [URL] = []
    private var draining = false
    private var engine: TranscriptionEngine?
    private var engineSelection: TranscriptionSelection?
    private var retryState = TranscriptionRetryState()
    private var statusHandler: (@Sendable (Status) -> Void)?
    private let notificationHandler: @Sendable (RecordNotification) -> Void
    private let refinementAdviser: any TranscriptRefinementAdvising

    init(
        notificationHandler: @escaping @Sendable (RecordNotification) -> Void = { _ in },
        refinementAdviser: any TranscriptRefinementAdvising =
            OnDeviceTranscriptRefinementAdviser()
    ) {
        self.notificationHandler = notificationHandler
        self.refinementAdviser = refinementAdviser
    }

    func setStatusHandler(_ handler: @escaping @Sendable (Status) -> Void) {
        statusHandler = handler
    }

    /// Queue a finished session. With transcription disabled in config, the
    /// completion hook still fires — it just gets an untranscribed folder.
    func enqueue(_ sessionDir: URL) {
        guard Config.transcriptionEnabled() else {
            runHook(for: sessionDir)
            return
        }
        appendIfNeeded(sessionDir)
        drainIfIdle()
    }

    /// Retry the most recent failed job without requiring an app restart or
    /// touching the recording. Returns false when there is nothing to retry.
    @discardableResult
    func retryLastFailure() -> Bool {
        guard Config.transcriptionEnabled(), let failedDirectory = retryState.takeFailure()
        else { return false }
        appendIfNeeded(failedDirectory)
        drainIfIdle()
        return true
    }

    /// Scan the recordings root for finalized sessions that were never
    /// transcribed. Legacy Quill `meta.json` sessions remain readable.
    func resumePending(root: URL, recoverInterrupted: Bool = true) {
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
        guard Config.transcriptionEnabled() else { return }
        let pending = Self.pendingSessionDirectories(root: root)
        for dir in pending {
            appendIfNeeded(dir)
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
            guard SessionMeta.isFinalized(directory) else { return false }
            guard
                !fileManager.fileExists(
                    atPath: directory.appendingPathComponent("transcript.json").path
                )
            else { return false }
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

    private func appendIfNeeded(_ directory: URL) {
        let directory = directory.standardizedFileURL
        guard !queue.contains(directory) else { return }
        queue.append(directory)
    }

    private func drain() async {
        while !queue.isEmpty {
            let dir = queue.removeFirst()
            publish(.transcribing(session: dir.lastPathComponent, queued: queue.count))
            do {
                try await transcribe(dir)
                notificationHandler(
                    RecordNotification(
                        title: "Transcript ready",
                        body: "Transcription finished. Click to open the recording folder.",
                        destinationDirectory: dir
                    )
                )
                runHook(for: dir)
            } catch {
                log(dir, "transcription failed: \(error)")
                retryState.recordFailure(in: dir)
                notificationHandler(
                    RecordNotification(
                        title: "Transcription couldn’t finish",
                        body:
                            "The recording is safe. Click to open its folder and review transcribe.log.",
                        destinationDirectory: dir
                    )
                )
            }
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

    private func transcribe(_ dir: URL) async throws {
        let meta = try SessionMeta.read(from: dir)
        let engine = try await preparedEngine()

        var merged: [TranscriptDocument.Segment] = []
        var attemptedTracks = 0
        var successfulTracks = 0
        for track in meta.tracks {
            attemptedTracks += 1
            let audio = dir.appendingPathComponent(track.file)
            guard FileManager.default.fileExists(atPath: audio.path) else {
                log(dir, "skipping missing track \(track.file)")
                continue
            }
            log(dir, "transcribing \(track.file) (\(engine.name))")
            // One bad track (empty, truncated) shouldn't cost us the other's
            // transcript — log it and keep going.
            let segments: [TranscriptSegment]
            do {
                segments = try await engine.transcribe(audio)
                successfulTracks += 1
            } catch {
                log(dir, "skipping \(track.file): \(error)")
                continue
            }
            let offset = TimeInterval(track.offsetMs) / 1000
            merged += segments.map {
                TranscriptDocument.Segment(
                    speaker: track.speaker,
                    startMilliseconds: Int(($0.start + offset) * 1000),
                    endMilliseconds: Int(($0.end + offset) * 1000),
                    text: $0.text
                )
            }
        }
        try Self.validateTrackResults(attempted: attemptedTracks, succeeded: successfulTracks)
        merged.sort { $0.startMilliseconds < $1.startMilliseconds }

        let rawTranscript = TranscriptDocument(
            engine: engine.name,
            model: engine.model,
            createdAt: ISO8601DateFormatter().string(from: Date()),
            segments: merged
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
        try? FileManager.default.removeItem(at: rawTranscriptURL)
        try? FileManager.default.removeItem(at: refinementReportURL)

        var finalSegments = suppression.segments
        var refinementChanged = false
        if Config.refineTranscriptWithAppleIntelligence() {
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
            refinementChanged = refinementPass.result.changed
            log(
                dir,
                "transcript refinement \(refinementPass.outcome.rawValue); removed "
                    + "\(refinementPass.result.removals.count) candidate(s), marked "
                    + "\(refinementPass.result.overlaps.count) overlap group(s)"
            )
        }

        if !suppression.suppressedMicrophoneSegments.isEmpty || refinementChanged {
            try rawTranscript.writeJSON(to: rawTranscriptURL)
            if !suppression.suppressedMicrophoneSegments.isEmpty {
                log(
                    dir,
                    "speaker echo suppression removed "
                        + "\(suppression.suppressedMicrophoneSegments.count) mic segment(s); "
                        + "unsuppressed segments are in transcript.raw.json"
                )
            }
        }
        let transcript = TranscriptDocument(
            engine: rawTranscript.engine,
            model: rawTranscript.model,
            createdAt: rawTranscript.createdAt,
            segments: finalSegments
        )
        try transcript.write(to: dir, title: dir.lastPathComponent)
        log(dir, "done — \(finalSegments.count) segments")
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
        try await newEngine.prepare()
        engine = newEngine
        engineSelection = selection
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

    var description: String {
        switch self {
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
        if let manifest = try? SessionManifest.read(from: dir) {
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
        if let manifest = try? SessionManifest.read(from: dir) {
            return manifest.state == .finalized || manifest.state == .interrupted
        }
        return FileManager.default.fileExists(
            atPath: dir.appendingPathComponent("meta.json").path
        )
    }
}
