import Foundation
import RecordCore

protocol SessionAudioRecording: AnyObject {
    var firstBufferAt: Date? { get }
    func start(writingTo url: URL) throws
    func stop()
}

extension MicRecorder: SessionAudioRecording {}
extension SystemAudioRecorder: SessionAudioRecording {}

/// One local recording session. A manifest is written before capture starts,
/// then atomically finalized after both audio tracks stop.
@MainActor
final class RecordingSession {
    enum SessionError: Error {
        case missingFinalizedAudio(SessionManifest.TrackKind)
    }

    let id: UUID
    let dir: URL
    let startedAt: Date

    private let health: CaptureHealthLedger
    private let mic: any SessionAudioRecording
    private let system: any SessionAudioRecording
    private let audioFinalizer: any SessionAudioFinalizing
    private var manifest: SessionManifest

    init(
        root: URL,
        startedAt: Date = Date(),
        id: UUID = UUID(),
        preparedSystemAudioTap: PreparedSystemAudioTap? = nil,
        mic: (any SessionAudioRecording)? = nil,
        system: (any SessionAudioRecording)? = nil,
        audioFinalizer: any SessionAudioFinalizing = PCM24WaveAudioFinalizer(),
        onHealth: @escaping @Sendable (CaptureHealthEvent) -> Void = { _ in }
    ) throws {
        self.id = id
        self.startedAt = startedAt
        let health = CaptureHealthLedger(onEvent: onHealth)
        self.health = health
        self.mic = mic ?? MicRecorder(startedAt: startedAt) { health.record($0) }
        self.system =
            system
            ?? SystemAudioRecorder(
                startedAt: startedAt,
                preparedTap: preparedSystemAudioTap
            ) { health.record($0) }
        self.audioFinalizer = audioFinalizer
        dir = try SessionFolderAllocator.createDirectory(
            under: root,
            startedAt: startedAt
        )
        manifest = SessionManifest(
            id: id,
            ownerProcessIdentifier: ProcessInfo.processInfo.processIdentifier,
            startedAt: startedAt,
            tracks: [
                SessionMediaLayout.track(for: .microphone, stage: .capture),
                SessionMediaLayout.track(for: .systemAudio, stage: .capture),
            ].compactMap { $0 }
        )
        try manifest.write(to: dir)
        health.setPersistence { [weak self] events in
            Task { @MainActor [weak self] in
                self?.persistHealthEvents(events)
            }
        }
    }

    /// Start both tracks. If microphone capture fails after the system tap is
    /// live, tear down the tap so a half-session never continues silently.
    func start() throws {
        try system.start(
            writingTo: SessionMediaLayout.url(
                for: .systemAudio,
                stage: .capture,
                in: dir
            )!
        )
        do {
            try mic.start(
                writingTo: SessionMediaLayout.url(
                    for: .microphone,
                    stage: .capture,
                    in: dir
                )!
            )
        } catch {
            system.stop()
            throw error
        }
    }

    /// Stop both tracks and atomically transition `session.json` to finalized.
    func stop(endedAt: Date = Date()) async throws {
        let micStart = mic.firstBufferAt ?? startedAt
        let systemStart = system.firstBufferAt ?? startedAt
        mic.stop()
        system.stop()

        let sources: [SessionAudioArtifact] = [
            .init(
                kind: .microphone,
                url: SessionMediaLayout.url(for: .microphone, stage: .capture, in: dir)!
            ),
            .init(
                kind: .systemAudio,
                url: SessionMediaLayout.url(for: .systemAudio, stage: .capture, in: dir)!
            ),
        ]
        let finalizer = audioFinalizer
        let finalizedAudio = try await Task.detached(priority: .utility) {
            try finalizer.finalize(sources)
        }.value
        guard
            let micOutput = finalizedAudio.first(where: { $0.kind == .microphone }),
            let systemOutput = finalizedAudio.first(where: { $0.kind == .systemAudio })
        else {
            throw SessionError.missingFinalizedAudio(
                finalizedAudio.contains(where: { $0.kind == .microphone })
                    ? .systemAudio : .microphone
            )
        }

        let earliest = min(micStart, systemStart)
        let tracks: [SessionManifest.Track] = [
            .init(
                kind: .microphone,
                filename: micOutput.url.lastPathComponent,
                speaker: SessionMediaLayout.defaultSpeaker(for: .microphone),
                startOffsetMilliseconds: Int(micStart.timeIntervalSince(earliest) * 1_000)
            ),
            .init(
                kind: .systemAudio,
                filename: systemOutput.url.lastPathComponent,
                speaker: SessionMediaLayout.defaultSpeaker(for: .systemAudio),
                startOffsetMilliseconds: Int(systemStart.timeIntervalSince(earliest) * 1_000)
            ),
        ]
        manifest.healthEvents = health.snapshot()
        manifest = try manifest.finalized(at: endedAt, tracks: tracks)
        try manifest.write(to: dir)
    }

    private func persistHealthEvents(_ events: [CaptureHealthEvent]) {
        guard manifest.state == .recording else { return }
        manifest.healthEvents = events.isEmpty ? nil : events
        do {
            try manifest.write(to: dir)
        } catch {
            FileHandle.standardError.write(
                Data("warning: capture health manifest update failed\n".utf8)
            )
        }
    }
}

private final class CaptureHealthLedger: @unchecked Sendable {
    private let lock = NSLock()
    private let onEvent: @Sendable (CaptureHealthEvent) -> Void
    private var events: [CaptureHealthEvent] = []
    private var persistence: (@Sendable ([CaptureHealthEvent]) -> Void)?

    init(onEvent: @escaping @Sendable (CaptureHealthEvent) -> Void) {
        self.onEvent = onEvent
    }

    func record(_ event: CaptureHealthEvent) {
        let (copy, persistence) = lock.withLock {
            () -> (
                [CaptureHealthEvent],
                (@Sendable ([CaptureHealthEvent]) -> Void)?
            ) in
            events.append(event)
            return (events, self.persistence)
        }
        persistence?(copy)
        onEvent(event)
    }

    func setPersistence(
        _ persistence: @escaping @Sendable ([CaptureHealthEvent]) -> Void
    ) {
        lock.withLock { self.persistence = persistence }
    }

    func snapshot() -> [CaptureHealthEvent]? {
        let copy = lock.withLock { events }
        return copy.isEmpty ? nil : copy
    }
}
