import Foundation
import RecordCore

/// Post-recording pipeline: a serial queue of session folders to transcribe.
/// mic.caf → "me", system.caf → "them"; each track's segments are shifted by
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
    private var lastFailure: String?
    private var statusHandler: (@Sendable (Status) -> Void)?

    func setStatusHandler(_ handler: @escaping @Sendable (Status) -> Void) {
        statusHandler = handler
    }

    /// Queue a finished session. With transcription disabled in config, the
    /// The completion hook still fires — it just gets an untranscribed folder.
    func enqueue(_ sessionDir: URL) {
        guard Config.transcriptionEnabled() else {
            runHook(for: sessionDir)
            return
        }
        queue.append(sessionDir)
        drainIfIdle()
    }

    /// Scan the recordings root for finalized sessions that were never
    /// transcribed. Legacy Quill `meta.json` sessions remain readable.
    func resumePending(root: URL) {
        guard Config.transcriptionEnabled() else { return }
        guard
            let entries = try? FileManager.default.contentsOfDirectory(
                at: root, includingPropertiesForKeys: nil
            )
        else { return }

        let fm = FileManager.default
        let pending =
            entries
            .filter {
                SessionMeta.isFinalized($0)
                    && !fm.fileExists(atPath: $0.appendingPathComponent("transcript.json").path)
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        for dir in pending where !queue.contains(dir) {
            queue.append(dir)
        }
        if !pending.isEmpty {
            FileHandle.standardError.write(
                Data(
                    "resuming \(pending.count) untranscribed session(s)\n".utf8
                ))
        }
        drainIfIdle()
    }

    // MARK: -

    private func drainIfIdle() {
        guard !draining, !queue.isEmpty else { return }
        draining = true
        lastFailure = nil
        Task { await drain() }
    }

    private func drain() async {
        while !queue.isEmpty {
            let dir = queue.removeFirst()
            publish(.transcribing(session: dir.lastPathComponent, queued: queue.count))
            do {
                try await transcribe(dir)
                notifyUser(title: "Record — transcript ready", body: dir.lastPathComponent)
                runHook(for: dir)
            } catch {
                log(dir, "transcription failed: \(error)")
                lastFailure = dir.lastPathComponent
                notifyUser(
                    title: "Record — transcription failed",
                    body: "\(dir.lastPathComponent) — see transcribe.log"
                )
            }
        }
        await engine?.release()
        engine = nil
        publish(lastFailure.map { .failed(session: $0) } ?? .idle)
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

        let transcript = TranscriptDocument(
            engine: engine.name,
            model: engine.model,
            createdAt: ISO8601DateFormatter().string(from: Date()),
            segments: merged
        )
        try transcript.write(to: dir, title: dir.lastPathComponent)
        log(dir, "done — \(merged.count) segments")
    }

    static func validateTrackResults(attempted: Int, succeeded: Int) throws {
        guard attempted == 0 || succeeded > 0 else {
            throw PipelineError.allTracksFailed(attempted)
        }
    }

    private func preparedEngine() async throws -> TranscriptionEngine {
        if let engine { return engine }
        let configured = Config.transcriptionEngine()
        let newEngine: TranscriptionEngine
        switch configured {
        case "parakeet":
            let configuredModel = Config.transcriptionModel() ?? ParakeetModelID.v3.rawValue
            let selection = try ParakeetModelID(configurationValue: configuredModel)
            newEngine = ParakeetEngine(selection: selection)
        case "macwhisper":
            guard
                let executable = MacWhisperExecutable.resolve(
                    configuredPath: Config.transcriptionExecutable()
                )
            else {
                throw MacWhisperEngine.EngineError.executableMissing(
                    URL(fileURLWithPath: Config.transcriptionExecutable() ?? "mw")
                )
            }
            let model = Config.transcriptionModel() ?? ""
            newEngine = try MacWhisperEngine(
                executable: executable,
                model: model,
                language: Config.transcriptionLanguage()
            )
        default:
            throw AppConfiguration.ConfigurationError.unsupportedTranscriptionEngine(configured)
        }
        try await newEngine.prepare()
        engine = newEngine
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

        var description: String {
            switch self {
            case .unreadable(let url): return "can't parse \(url.path)"
            }
        }
    }

    static func read(from dir: URL) throws -> SessionMeta {
        if let manifest = try? SessionManifest.read(from: dir) {
            guard manifest.state == .finalized else {
                throw MetaError.unreadable(dir.appendingPathComponent("session.json"))
            }
            let tracks = manifest.tracks.compactMap { track -> Track? in
                switch track.kind {
                case .microphone:
                    return Track(
                        file: track.filename,
                        speaker: track.speaker ?? "me",
                        offsetMs: track.startOffsetMilliseconds
                    )
                case .systemAudio:
                    return Track(
                        file: track.filename,
                        speaker: track.speaker ?? "them",
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
            tracks.append(Track(file: mic, speaker: "me", offsetMs: offsets["mic"] ?? 0))
        }
        if let system = files["system"] {
            tracks.append(Track(file: system, speaker: "them", offsetMs: offsets["system"] ?? 0))
        }
        return SessionMeta(tracks: tracks)
    }

    static func isFinalized(_ dir: URL) -> Bool {
        if let manifest = try? SessionManifest.read(from: dir) {
            return manifest.state == .finalized
        }
        return FileManager.default.fileExists(
            atPath: dir.appendingPathComponent("meta.json").path
        )
    }
}
