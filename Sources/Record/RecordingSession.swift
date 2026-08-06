import Foundation
import RecordCore

/// One local recording session. A manifest is written before capture starts,
/// then atomically finalized after both audio tracks stop.
final class RecordingSession {
    let id: UUID
    let dir: URL
    let startedAt: Date

    private let mic = MicRecorder()
    private let system = SystemAudioRecorder()
    private var manifest: SessionManifest

    init(root: URL, startedAt: Date = Date(), id: UUID = UUID()) throws {
        self.id = id
        self.startedAt = startedAt
        dir = try SessionFolderAllocator.createDirectory(
            under: root,
            startedAt: startedAt
        )
        manifest = SessionManifest(
            id: id,
            startedAt: startedAt,
            tracks: [
                .init(kind: .microphone, filename: "mic.caf", speaker: "me"),
                .init(kind: .systemAudio, filename: "system.caf", speaker: "them"),
            ]
        )
        try manifest.write(to: dir)
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
        manifest = try manifest.finalized(at: endedAt, tracks: tracks)
        try manifest.write(to: dir)
    }
}
