import Foundation
import RecordCore

/// One local recording session. A manifest is written before capture starts,
/// then atomically finalized after both audio tracks stop.
@MainActor
final class RecordingSession {
    let id: UUID
    let dir: URL
    let startedAt: Date

    private let health: CaptureHealthLedger
    private let mic: MicRecorder
    private let system: SystemAudioRecorder
    private var manifest: SessionManifest

    init(
        root: URL,
        startedAt: Date = Date(),
        id: UUID = UUID(),
        onHealth: @escaping @Sendable (CaptureHealthEvent) -> Void = { _ in }
    ) throws {
        self.id = id
        self.startedAt = startedAt
        let health = CaptureHealthLedger(onEvent: onHealth)
        self.health = health
        mic = MicRecorder(startedAt: startedAt) { health.record($0) }
        system = SystemAudioRecorder(startedAt: startedAt) { health.record($0) }
        dir = try SessionFolderAllocator.createDirectory(
            under: root,
            startedAt: startedAt
        )
        manifest = SessionManifest(
            id: id,
            ownerProcessIdentifier: ProcessInfo.processInfo.processIdentifier,
            startedAt: startedAt,
            tracks: [
                .init(kind: .microphone, filename: "mic.caf", speaker: "me"),
                .init(kind: .systemAudio, filename: "system.caf", speaker: "them"),
            ]
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
        try system.start(writingTo: dir.appendingPathComponent("system.caf"))
        do {
            try mic.start(writingTo: dir.appendingPathComponent("mic.caf"))
        } catch {
            system.stop()
            throw error
        }
    }

    /// Stop both tracks and atomically transition `session.json` to finalized.
    func stop(endedAt: Date = Date()) throws {
        mic.stop()
        system.stop()

        let micStart = mic.firstBufferAt ?? startedAt
        let systemStart = system.firstBufferAt ?? startedAt
        let earliest = min(micStart, systemStart)
        let tracks: [SessionManifest.Track] = [
            .init(
                kind: .microphone,
                filename: "mic.caf",
                speaker: "me",
                startOffsetMilliseconds: Int(micStart.timeIntervalSince(earliest) * 1_000)
            ),
            .init(
                kind: .systemAudio,
                filename: "system.caf",
                speaker: "them",
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
        let (copy, persistence) = lock.withLock { () -> (
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
