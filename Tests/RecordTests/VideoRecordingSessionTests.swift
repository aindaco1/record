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

        try await session.start(configuration: fixture.configuration, at: fixture.startedAt)
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
            try await session.start(configuration: fixture.configuration, at: fixture.startedAt)
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

        try await session.start(configuration: fixture.configuration, at: fixture.startedAt)
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
            try await session.start(configuration: fixture.configuration, at: fixture.startedAt)
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

        try await session.start(configuration: fixture.configuration, at: fixture.startedAt)
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

    func testPauseResumeRotatesImmutableSegmentsAndRecordsIdempotentEvents() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let builder = FakeVideoCapturePipelineBuilder(behavior: .success)
        let combiner = FakeVideoSegmentCombiner()
        let session = try VideoRecordingSession(
            root: fixture.root,
            startedAt: fixture.startedAt,
            pipelineBuilder: builder,
            segmentCombiner: combiner,
            eventHandler: { _ in }
        )

        try await session.start(configuration: fixture.configuration, at: fixture.startedAt)
        try await session.pause(at: fixture.startedAt.addingTimeInterval(3))
        try await session.pause(at: fixture.startedAt.addingTimeInterval(3))
        let paused = await session.isPaused()
        XCTAssertTrue(paused)
        try await session.resume(at: fixture.startedAt.addingTimeInterval(4))
        try await session.resume(at: fixture.startedAt.addingTimeInterval(4))
        let outcome = try await session.stop(endedAt: fixture.endedAt)

        XCTAssertEqual(outcome.state, .finalized)
        XCTAssertEqual(builder.counts, .init(starts: 2, stops: 2))
        XCTAssertEqual(combiner.combinedSegmentIndices, [1, 2])
        for filename in [
            "segment-0001.mov", "segment-0001-system.caf", "segment-0001-mic.caf",
            "segment-0002.mov", "segment-0002-system.caf", "segment-0002-mic.caf",
        ] {
            XCTAssertTrue(
                FileManager.default.fileExists(
                    atPath: session.dir.appendingPathComponent(filename).path
                )
            )
        }
        let manifest = try SessionManifest.read(from: session.dir)
        XCTAssertNil(manifest.captureSegments)
        XCTAssertEqual(
            manifest.captureEvents,
            [
                .init(kind: .started, occurredAtMilliseconds: 0, segmentIndex: 1),
                .init(kind: .paused, occurredAtMilliseconds: 3_000, segmentIndex: 1),
                .init(kind: .resumed, occurredAtMilliseconds: 4_000, segmentIndex: 2),
                .init(kind: .stopped, occurredAtMilliseconds: 10_000, segmentIndex: 2),
            ]
        )
    }

    func testStopWhilePausedFinalizesTheCompletedSegment() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let builder = FakeVideoCapturePipelineBuilder(behavior: .success)
        let combiner = FakeVideoSegmentCombiner()
        let session = try VideoRecordingSession(
            root: fixture.root,
            startedAt: fixture.startedAt,
            pipelineBuilder: builder,
            segmentCombiner: combiner,
            eventHandler: { _ in }
        )

        try await session.start(configuration: fixture.configuration, at: fixture.startedAt)
        try await session.pause(at: fixture.startedAt.addingTimeInterval(3))
        let outcome = try await session.stop(endedAt: fixture.endedAt)

        XCTAssertEqual(outcome.state, .finalized)
        XCTAssertEqual(builder.counts, .init(starts: 1, stops: 1))
        XCTAssertEqual(combiner.combinedSegmentIndices, [1])
    }

    func testResumeFailurePreservesTheCompletedSegmentAndManifestJournal() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let failure = CaptureFailure(
            code: .permissionDenied,
            summary: "screen recording permission was denied"
        )
        let builder = FakeVideoCapturePipelineBuilder(
            behaviors: [.success, .startFailure(failure)]
        )
        let session = try VideoRecordingSession(
            root: fixture.root,
            startedAt: fixture.startedAt,
            pipelineBuilder: builder,
            eventHandler: { _ in }
        )

        try await session.start(configuration: fixture.configuration, at: fixture.startedAt)
        try await session.pause(at: fixture.startedAt.addingTimeInterval(3))
        await XCTAssertThrowsErrorAsync(
            try await session.resume(at: fixture.startedAt.addingTimeInterval(4))
        ) { error in
            XCTAssertEqual(error as? VideoRecordingSession.SessionError, .captureFailed(failure))
        }

        let manifest = try SessionManifest.read(from: session.dir)
        XCTAssertEqual(manifest.state, .failed)
        XCTAssertEqual(manifest.captureSegments?.count, 2)
        XCTAssertEqual(manifest.captureSegments?.first?.endedAtMilliseconds, 3_000)
        XCTAssertNil(manifest.captureSegments?.last?.endedAtMilliseconds)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: session.dir.appendingPathComponent("segment-0001.mov").path
            )
        )
    }

    func testStopWaitsForAnInFlightPauseRotation() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let builder = FakeVideoCapturePipelineBuilder(behavior: .successWithStopDelay)
        let session = try VideoRecordingSession(
            root: fixture.root,
            startedAt: fixture.startedAt,
            pipelineBuilder: builder,
            segmentCombiner: FakeVideoSegmentCombiner(),
            eventHandler: { _ in }
        )
        try await session.start(configuration: fixture.configuration, at: fixture.startedAt)

        let pauseTask = Task {
            try await session.pause(at: fixture.startedAt.addingTimeInterval(3))
        }
        while builder.counts.stops == 0 { await Task.yield() }
        let outcome = try await session.stop(endedAt: fixture.endedAt)
        try await pauseTask.value

        XCTAssertEqual(outcome.state, .finalized)
        XCTAssertEqual(builder.counts, .init(starts: 1, stops: 1))
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

private final class FakeVideoSegmentCombiner: VideoSegmentCombining, @unchecked Sendable {
    private let lock = NSLock()
    private var indices: [Int] = []

    var combinedSegmentIndices: [Int] { lock.withLock { indices } }

    func combine(
        _ segments: [CaptureSegmentArtifactSet],
        in directory: URL
    ) async throws -> FinalizedSegmentArtifacts {
        lock.withLock { indices = segments.map(\.index) }
        let names: [ScreenCaptureSampleKind: String] = [
            .screen: "recording.mov",
            .systemAudio: "system.caf",
            .microphone: "mic.caf",
        ]
        var files: [ScreenCaptureSampleKind: URL] = [:]
        for kind in ScreenCaptureSampleKind.allCases {
            let payload = try segments.compactMap { segment -> Data? in
                guard let url = segment.artifacts[kind] else { return nil }
                return try Data(contentsOf: url)
            }.reduce(into: Data()) { $0.append($1) }
            guard !payload.isEmpty, let name = names[kind] else { continue }
            let url = directory.appendingPathComponent(name)
            try payload.write(to: url, options: .atomic)
            files[kind] = url
        }
        return FinalizedSegmentArtifacts(files: files)
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
        case successWithStopDelay
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
        selection: SystemScreenCaptureSelection?,
        outputURLs: VideoCaptureOutputURLs,
        onEvent: @escaping @Sendable (ScreenCaptureEvent) -> Void
    ) async throws -> any VideoCapturePipeline {
        let behavior = lock.withLock {
            behaviors[min(pipelines.count, behaviors.count - 1)]
        }
        let pipeline = FakeVideoCapturePipeline(outputURLs: outputURLs, behavior: behavior)
        lock.withLock { pipelines.append(pipeline) }
        return pipeline
    }
}

private final class FakeVideoCapturePipeline: VideoCapturePipeline, @unchecked Sendable {
    private let outputURLs: VideoCaptureOutputURLs
    private let behavior: FakeVideoCapturePipelineBuilder.Behavior
    private let lock = NSLock()
    private var startCount = 0
    private var stopCount = 0

    init(
        outputURLs: VideoCaptureOutputURLs,
        behavior: FakeVideoCapturePipelineBuilder.Behavior
    ) {
        self.outputURLs = outputURLs
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
        if case .successWithStopDelay = behavior {
            try? await Task.sleep(for: .milliseconds(50))
        }
        guard case .startFailure = behavior else {
            let payloads: [ScreenCaptureSampleKind: String] = [
                .screen: "movie",
                .systemAudio: "system",
                .microphone: "microphone",
            ]
            for (kind, url) in outputURLs.files {
                try? Data((payloads[kind] ?? "media").utf8).write(to: url)
            }
            let failure: CaptureFailure?
            if case .stopFailureWithMedia(let value) = behavior {
                failure = value
            } else {
                failure = nil
            }
            return VideoCapturePipelineStopResult(
                artifacts: FinalizedSegmentArtifacts(
                    files: outputURLs.files
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
