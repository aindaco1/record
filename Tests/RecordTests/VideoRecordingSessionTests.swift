import Foundation
@testable import Record
import RecordCapture
import RecordCore
import RecordMedia
import XCTest

final class VideoRecordingSessionTests: XCTestCase {
    func testCleanStopFinalizesVideoAndTwoIndependentAudioTracks() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let builder = FakeVideoCapturePipelineBuilder(behavior: .success)
        let session = try VideoRecordingSession(
            root: fixture.root,
            startedAt: fixture.startedAt,
            pipelineBuilder: builder,
            eventHandler: { _ in }
        )

        try await session.start(configuration: fixture.configuration)
        let first = try await session.stop(endedAt: fixture.endedAt)
        let second = try await session.stop(endedAt: fixture.endedAt.addingTimeInterval(1))

        XCTAssertEqual(first.state, .finalized)
        XCTAssertEqual(first.mediaURL, second.mediaURL)
        XCTAssertEqual(builder.counts, .init(starts: 1, stops: 1))
        let manifest = try SessionManifest.read(from: session.dir)
        XCTAssertEqual(manifest.state, .finalized)
        XCTAssertEqual(manifest.endedAt, fixture.endedAt)
        XCTAssertEqual(
            manifest.tracks,
            [
                .init(kind: .screen, filename: "recording.mov"),
                .init(kind: .systemAudio, filename: "system.caf", speaker: "them"),
                .init(kind: .microphone, filename: "mic.caf", speaker: "me"),
            ]
        )
    }

    func testStartFailureWritesFailedManifest() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let failure = CaptureFailure(
            code: .permissionDenied,
            summary: "screen recording permission was denied"
        )
        let builder = FakeVideoCapturePipelineBuilder(behavior: .startFailure(failure))
        let session = try VideoRecordingSession(
            root: fixture.root,
            startedAt: fixture.startedAt,
            pipelineBuilder: builder,
            eventHandler: { _ in }
        )

        await XCTAssertThrowsErrorAsync(
            try await session.start(configuration: fixture.configuration)
        ) { error in
            XCTAssertEqual(
                error as? VideoRecordingSession.SessionError,
                .captureFailed(failure)
            )
        }
        let manifest = try SessionManifest.read(from: session.dir)
        XCTAssertEqual(manifest.state, .failed)
        XCTAssertNotNil(manifest.endedAt)
        XCTAssertEqual(manifest.tracks.count, 3)
        XCTAssertEqual(manifest.failure, failure)
        XCTAssertEqual(builder.counts, .init(starts: 1, stops: 1))
    }

    func testTransientStartupFailuresRetryWithFreshPipelines() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let firstFailure = CaptureFailure(
            code: .internalFailure,
            summary: "shareable content was still settling"
        )
        let secondFailure = CaptureFailure(
            code: .sourceUnavailable,
            summary: "display list was temporarily empty"
        )
        let builder = FakeVideoCapturePipelineBuilder(
            behaviors: [
                .startFailure(firstFailure),
                .startFailure(secondFailure),
                .success,
            ]
        )
        let session = try VideoRecordingSession(
            root: fixture.root,
            startedAt: fixture.startedAt,
            pipelineBuilder: builder,
            startupRetryPolicy: .init(delays: [.zero, .zero]),
            eventHandler: { _ in }
        )

        try await session.start(configuration: fixture.configuration)
        let outcome = try await session.stop(endedAt: fixture.endedAt)

        XCTAssertEqual(outcome.state, .finalized)
        XCTAssertEqual(builder.pipelineCount, 3)
        XCTAssertEqual(builder.counts, .init(starts: 3, stops: 3))
    }

    func testPermissionFailureIsNeverRetried() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let failure = CaptureFailure(
            code: .permissionDenied,
            summary: "screen recording permission was denied"
        )
        let builder = FakeVideoCapturePipelineBuilder(
            behaviors: [.startFailure(failure), .success]
        )
        let session = try VideoRecordingSession(
            root: fixture.root,
            startedAt: fixture.startedAt,
            pipelineBuilder: builder,
            startupRetryPolicy: .init(delays: [.zero, .zero]),
            eventHandler: { _ in }
        )

        await XCTAssertThrowsErrorAsync(
            try await session.start(configuration: fixture.configuration)
        ) { error in
            XCTAssertEqual(
                error as? VideoRecordingSession.SessionError,
                .captureFailed(failure)
            )
        }

        XCTAssertEqual(builder.pipelineCount, 1)
        XCTAssertEqual(builder.counts, .init(starts: 1, stops: 1))
    }

    func testWriterFailurePreservesFinalizedMediaInFailedManifest() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let failure = CaptureFailure(code: .writerFailed, summary: "writer stalled")
        let builder = FakeVideoCapturePipelineBuilder(
            behavior: .stopFailureWithMedia(failure)
        )
        let session = try VideoRecordingSession(
            root: fixture.root,
            startedAt: fixture.startedAt,
            pipelineBuilder: builder,
            eventHandler: { _ in }
        )

        try await session.start(configuration: fixture.configuration)
        let outcome = try await session.stop(endedAt: fixture.endedAt)

        XCTAssertEqual(outcome.state, .failed)
        XCTAssertNotNil(outcome.mediaURL)
        let manifest = try SessionManifest.read(from: session.dir)
        XCTAssertEqual(manifest.state, .failed)
        XCTAssertEqual(
            manifest.tracks,
            [
                .init(kind: .screen, filename: "recording.mov"),
                .init(kind: .systemAudio, filename: "system.caf", speaker: "them"),
                .init(kind: .microphone, filename: "mic.caf", speaker: "me"),
            ]
        )
    }

    private func makeFixture() throws -> (
        root: URL,
        startedAt: Date,
        endedAt: Date,
        configuration: CaptureConfiguration
    ) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "record-video-session-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return (
            root,
            Date(timeIntervalSince1970: 100),
            Date(timeIntervalSince1970: 110),
            try VideoCaptureProfile.configuration(
                displayID: 1,
                pixelWidth: 1_920,
                pixelHeight: 1_080
            )
        )
    }
}

private final class FakeVideoCapturePipelineBuilder: VideoCapturePipelineBuilding,
    @unchecked Sendable
{
    struct Counts: Equatable {
        let starts: Int
        let stops: Int
    }

    enum Behavior: Sendable {
        case success
        case startFailure(CaptureFailure)
        case stopFailureWithMedia(CaptureFailure)
    }

    private let behaviors: [Behavior]
    private let lock = NSLock()
    private var pipelines: [FakeVideoCapturePipeline] = []

    init(behavior: Behavior) {
        behaviors = [behavior]
    }

    init(behaviors: [Behavior]) {
        precondition(!behaviors.isEmpty)
        self.behaviors = behaviors
    }

    var counts: Counts {
        lock.withLock {
            Counts(
                starts: pipelines.reduce(0) { $0 + $1.starts },
                stops: pipelines.reduce(0) { $0 + $1.stops }
            )
        }
    }

    var pipelineCount: Int { lock.withLock { pipelines.count } }

    func makePipeline(
        configuration: CaptureConfiguration,
        outputURL: URL,
        onEvent: @escaping @Sendable (ScreenCaptureEvent) -> Void
    ) async throws -> any VideoCapturePipeline {
        let behavior = lock.withLock {
            behaviors[min(pipelines.count, behaviors.count - 1)]
        }
        let pipeline = FakeVideoCapturePipeline(outputURL: outputURL, behavior: behavior)
        lock.withLock { pipelines.append(pipeline) }
        return pipeline
    }
}

private final class FakeVideoCapturePipeline: VideoCapturePipeline, @unchecked Sendable {
    private let outputURL: URL
    private let behavior: FakeVideoCapturePipelineBuilder.Behavior
    private let lock = NSLock()
    private var startCount = 0
    private var stopCount = 0

    init(
        outputURL: URL,
        behavior: FakeVideoCapturePipelineBuilder.Behavior
    ) {
        self.outputURL = outputURL
        self.behavior = behavior
    }

    var starts: Int { lock.withLock { startCount } }
    var stops: Int { lock.withLock { stopCount } }

    func start() async throws {
        lock.withLock { startCount += 1 }
        if case .startFailure(let failure) = behavior {
            throw ScreenCaptureAdapterError.captureFailed(failure)
        }
    }

    func stop() async -> VideoCapturePipelineStopResult {
        lock.withLock { stopCount += 1 }
        guard case .startFailure = behavior else {
            try? Data("movie".utf8).write(to: outputURL)
            let systemURL = outputURL.deletingLastPathComponent().appendingPathComponent(
                "system.caf"
            )
            let microphoneURL = outputURL.deletingLastPathComponent().appendingPathComponent(
                "mic.caf"
            )
            try? Data("system".utf8).write(to: systemURL)
            try? Data("microphone".utf8).write(to: microphoneURL)
            let failure: CaptureFailure?
            if case .stopFailureWithMedia(let value) = behavior {
                failure = value
            } else {
                failure = nil
            }
            return VideoCapturePipelineStopResult(
                artifacts: FinalizedSegmentArtifacts(
                    files: [
                        .screen: outputURL,
                        .systemAudio: systemURL,
                        .microphone: microphoneURL,
                    ]
                ),
                failure: failure,
                ingress: MediaIngressSnapshot()
            )
        }
        return VideoCapturePipelineStopResult(
            artifacts: nil,
            failure: nil,
            ingress: MediaIngressSnapshot()
        )
    }
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ handler: (Error) -> Void
) async {
    do {
        _ = try await expression()
        XCTFail("expected expression to throw")
    } catch {
        handler(error)
    }
}
