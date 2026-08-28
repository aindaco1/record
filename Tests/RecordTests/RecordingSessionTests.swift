import Foundation
@testable import Record
import RecordCore
import XCTest

@MainActor
final class RecordingSessionTests: XCTestCase {
    func testCleanStopFinalizesAudioOnlyManifestWithWaveTracks() async throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let microphone = FakeSessionAudioRecorder(firstBufferAt: Date(timeIntervalSince1970: 101))
        let system = FakeSessionAudioRecorder(firstBufferAt: Date(timeIntervalSince1970: 100))
        let session = try RecordingSession(
            root: root,
            startedAt: Date(timeIntervalSince1970: 100),
            mic: microphone,
            system: system,
            audioFinalizer: FakeSessionAudioFinalizer()
        )

        try session.start()
        try await session.stop(endedAt: Date(timeIntervalSince1970: 110))

        let manifest = try SessionManifest.read(from: session.dir)
        XCTAssertEqual(manifest.state, .finalized)
        XCTAssertEqual(
            manifest.tracks,
            [
                .init(
                    kind: .microphone,
                    filename: "mic.wav",
                    speaker: "me",
                    startOffsetMilliseconds: 1_000
                ),
                .init(kind: .systemAudio, filename: "system.wav", speaker: "them"),
            ]
        )
        for filename in ["mic.caf", "system.caf", "mic.wav", "system.wav"] {
            XCTAssertTrue(
                FileManager.default.fileExists(
                    atPath: session.dir.appendingPathComponent(filename).path
                )
            )
        }
        XCTAssertEqual(microphone.stopCount, 1)
        XCTAssertEqual(system.stopCount, 1)
    }

    func testWaveFinalizationFailureLeavesRecoverableCAFManifest() async throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let session = try RecordingSession(
            root: root,
            startedAt: Date(timeIntervalSince1970: 100),
            mic: FakeSessionAudioRecorder(),
            system: FakeSessionAudioRecorder(),
            audioFinalizer: FailingSessionAudioFinalizer()
        )

        try session.start()
        do {
            try await session.stop()
            XCTFail("expected WAV finalization to fail")
        } catch {
            // The manifest and CAF assertions below are the regression contract.
        }

        let manifest = try SessionManifest.read(from: session.dir)
        XCTAssertEqual(manifest.state, .recording)
        XCTAssertEqual(manifest.tracks.map(\.filename), ["mic.caf", "system.caf"])
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: session.dir.appendingPathComponent("mic.caf").path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: session.dir.appendingPathComponent("system.caf").path
            )
        )
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "record-audio-session-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

private final class FakeSessionAudioRecorder: SessionAudioRecording {
    let firstBufferAt: Date?
    private(set) var stopCount = 0

    init(firstBufferAt: Date? = nil) {
        self.firstBufferAt = firstBufferAt
    }

    func start(writingTo url: URL) throws {
        try Data("recoverable caf".utf8).write(to: url)
    }

    func stop() {
        stopCount += 1
    }
}

private struct FakeSessionAudioFinalizer: SessionAudioFinalizing {
    func finalize(_ sources: [SessionAudioArtifact]) throws -> [SessionAudioArtifact] {
        try sources.map { source in
            let filename = try XCTUnwrap(PCM24WaveAudioFinalizer.outputFilename(for: source.kind))
            let output = source.url.deletingLastPathComponent().appendingPathComponent(filename)
            try Data("wave".utf8).write(to: output)
            return SessionAudioArtifact(kind: source.kind, url: output)
        }
    }
}

private struct FailingSessionAudioFinalizer: SessionAudioFinalizing {
    struct Failure: Error {}

    func finalize(_: [SessionAudioArtifact]) throws -> [SessionAudioArtifact] {
        throw Failure()
    }
}
