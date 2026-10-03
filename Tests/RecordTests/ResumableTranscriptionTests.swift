import Foundation
@testable import Record
import RecordCore
import XCTest

final class ResumableTranscriptionTests: XCTestCase, @unchecked Sendable {
    func testDeferringDuringEnginePreparationDoesNotReportLateEngineErrorAsFailure() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let session = root.appendingPathComponent("synthetic", isDirectory: true)
        try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try SessionManifest(
            state: .finalized, startedAt: Date(timeIntervalSince1970: 1),
            endedAt: Date(timeIntervalSince1970: 2),
            tracks: [.init(kind: .microphone, filename: "mic.wav")]
        ).write(to: session)
        let started = expectation(description: "preparation started")
        let drained = expectation(description: "deferred without failure")
        let engine = SuspendedEngine(suspendPreparation: true, onStart: { started.fulfill() })
        let coordinator = TranscriptionCoordinator(
            notificationHandler: { _ in XCTFail("Deferring must not report a failure or completion")
            },
            engineFactory: { _ in engine }, refinementEnabled: { false },
            transcriptionEnabled: { true })
        await coordinator.setStatusHandler { status in
            if case .idle = status { drained.fulfill() }
            if case .failed = status { XCTFail("Cancelled preparation is deferred") }
        }
        await coordinator.enqueue(session)
        await fulfillment(of: [started], timeout: 3)
        try await coordinator.deferSession(session)
        await engine.finish()
        await fulfillment(of: [drained], timeout: 3)
        XCTAssertEqual(try TranscriptionCheckpoint.read(from: session).state, .deferred)
        XCTAssertTrue(TranscriptionCoordinator.pendingSessionDirectories(root: root).isEmpty)
    }

    func testDeferralDuringInferencePreservesLateSuccessWithoutRestartingOrDuplicatingJob()
        async throws
    {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let session = root.appendingPathComponent("synthetic", isDirectory: true)
        try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try SessionManifest(
            state: .finalized, startedAt: Date(timeIntervalSince1970: 1),
            endedAt: Date(timeIntervalSince1970: 2),
            tracks: [.init(kind: .microphone, filename: "mic.wav")]
        ).write(to: session)
        try Data("synthetic audio".utf8).write(to: session.appendingPathComponent("mic.wav"))
        let started = expectation(description: "inference started")
        let drained = expectation(description: "queue drained")
        let engine = SuspendedEngine(onStart: { started.fulfill() })
        let coordinator = TranscriptionCoordinator(
            engineFactory: { _ in engine }, refinementEnabled: { false },
            transcriptionEnabled: { true })
        await coordinator.setStatusHandler { status in if case .idle = status { drained.fulfill() }
        }
        await coordinator.enqueue(session)
        await fulfillment(of: [started], timeout: 3)
        let alias = URL(fileURLWithPath: session.resolvingSymlinksInPath().path)
        await coordinator.enqueue(alias)
        try await coordinator.deferSession(alias)
        await engine.finish()
        await fulfillment(of: [drained], timeout: 3)
        let checkpoint = try TranscriptionCheckpoint.read(from: session)
        XCTAssertEqual(checkpoint.state, .deferred)
        XCTAssertEqual(checkpoint.completedTracks, 1)
        XCTAssertTrue(TranscriptionCoordinator.pendingSessionDirectories(root: root).isEmpty)
        let calls = await engine.calls
        XCTAssertEqual(calls, 1)
    }

    func testPartialFailurePublishesClearlyAndRetryOnlyProcessesFailedTrack() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let session = root.appendingPathComponent("synthetic")
        try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try SessionManifest(
            state: .finalized, startedAt: Date(timeIntervalSince1970: 1),
            endedAt: Date(timeIntervalSince1970: 2),
            tracks: [
                .init(kind: .microphone, filename: "mic.wav", speaker: "me"),
                .init(
                    kind: .systemAudio, filename: "system.wav", speaker: "them",
                    startOffsetMilliseconds: 100),
            ]
        ).write(to: session)
        for filename in ["mic.wav", "system.wav"] {
            try Data("synthetic source".utf8).write(to: session.appendingPathComponent(filename))
        }
        let engine = RetryEngine()
        let coordinator = TranscriptionCoordinator(
            engineFactory: { _ in engine }, refinementEnabled: { false },
            transcriptionEnabled: { true })
        do {
            try await coordinator.transcribe(session)
            XCTFail("a partial result must not be reported complete")
        } catch { XCTAssertEqual(error as? PipelineError, .partialTracksFailed(1)) }
        var checkpoint = try TranscriptionCheckpoint.read(from: session)
        XCTAssertEqual(checkpoint.state, .needsRetry)
        XCTAssertEqual(checkpoint.completedTracks, 1)
        let partial = try JSONDecoder().decode(
            TranscriptDocument.self,
            from: Data(contentsOf: session.appendingPathComponent("transcript.json")))
        XCTAssertEqual(partial.incompleteTrackCount, 1)
        XCTAssertTrue(
            try String(contentsOf: session.appendingPathComponent("transcript.md"), encoding: .utf8)
                .contains("Partial transcript"))
        XCTAssertEqual(
            TranscriptionCoordinator.pendingSessionDirectories(root: root).map {
                $0.resolvingSymlinksInPath().path
            }, [session.resolvingSymlinksInPath().path])

        // Reopening the app uses the checkpoint, not an in-memory cache.
        let reopened = TranscriptionCoordinator(
            engineFactory: { _ in engine }, refinementEnabled: { false },
            transcriptionEnabled: { true })
        try await reopened.transcribe(session)
        checkpoint = try TranscriptionCheckpoint.read(from: session)
        XCTAssertEqual(checkpoint.state, .complete)
        XCTAssertEqual(checkpoint.completedTracks, 2)
        let calls = await engine.calls
        XCTAssertEqual(calls, ["mic.wav", "system.wav", "system.wav"])
        XCTAssertTrue(TranscriptionCoordinator.pendingSessionDirectories(root: root).isEmpty)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: session.appendingPathComponent("mic.wav").path))
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: session.appendingPathComponent("system.wav").path))
    }

    func testDeferredSessionDoesNotRestartOnLaunch() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let session = root.appendingPathComponent("synthetic")
        try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try SessionManifest(
            state: .finalized, startedAt: Date(timeIntervalSince1970: 1),
            endedAt: Date(timeIntervalSince1970: 2),
            tracks: [.init(kind: .microphone, filename: "mic.wav")]
        ).write(to: session)
        XCTAssertEqual(
            TranscriptionCoordinator.pendingSessionDirectories(root: root).map {
                $0.resolvingSymlinksInPath().path
            }, [session.resolvingSymlinksInPath().path])
        try await TranscriptionCoordinator().deferSession(session)
        XCTAssertTrue(TranscriptionCoordinator.pendingSessionDirectories(root: root).isEmpty)
        XCTAssertEqual(try TranscriptionCheckpoint.read(from: session).state, .deferred)
    }
}

private actor SuspendedEngine: TranscriptionEngine {
    nonisolated let name = "synthetic"
    nonisolated let model = "test"
    let onStart: @Sendable () -> Void
    let suspendPreparation: Bool
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var calls = 0
    init(suspendPreparation: Bool = false, onStart: @escaping @Sendable () -> Void) {
        self.suspendPreparation = suspendPreparation
        self.onStart = onStart
    }
    func prepare() async throws {
        if suspendPreparation {
            await waitForFinish()
            throw PipelineError.unreadableTrack
        }
    }
    func release() async {}
    func transcribe(_ audio: URL) async throws -> [TranscriptSegment] {
        calls += 1
        await waitForFinish()
        return [.init(start: 0, end: 1, text: "Preserved synthetic speech.")]
    }
    private func waitForFinish() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            onStart()
        }
    }
    func finish() { continuation?.resume(); continuation = nil }
}

private actor RetryEngine: TranscriptionEngine {
    nonisolated let name = "synthetic"
    nonisolated let model = "test"
    private(set) var calls: [String] = []
    func prepare() async throws {}
    func release() async {}
    func transcribe(_ audio: URL) async throws -> [TranscriptSegment] {
        let filename = audio.lastPathComponent
        calls.append(filename)
        if filename == "system.wav", calls.filter({ $0 == filename }).count == 1 {
            throw PipelineError.unreadableTrack
        }
        return [
            .init(
                start: 0, end: 1,
                text: filename == "mic.wav" ? "The first speaker." : "The second speaker.")
        ]
    }
}
