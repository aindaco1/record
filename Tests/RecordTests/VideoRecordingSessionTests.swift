import Foundation
@testable import Record
import RecordCapture
import RecordCore
import RecordMedia
import XCTest

final class VideoRecordingSessionTests: XCTestCase {
    func testCleanStopFinalizesOneImmutableScreenTrack() async throws {
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
            [.init(kind: .screen, filename: "recording.mov")]
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
        XCTAssertTrue(manifest.tracks.isEmpty)
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
        XCTAssertEqual(manifest.tracks, [.init(kind: .screen, filename: "recording.mov")])
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

    private let behavior: Behavior
    private let lock = NSLock()
    private var pipeline: FakeVideoCapturePipeline?

    init(behavior: Behavior) {
        self.behavior = behavior
    }

    var counts: Counts {
        lock.withLock {
            Counts(
                starts: pipeline?.starts ?? 0,
                stops: pipeline?.stops ?? 0
            )
        }
    }

    func makePipeline(
        configuration: CaptureConfiguration,
        outputURL: URL,
        onEvent: @escaping @Sendable (ScreenCaptureEvent) -> Void
    ) async throws -> any VideoCapturePipeline {
        let pipeline = FakeVideoCapturePipeline(outputURL: outputURL, behavior: behavior)
        lock.withLock { self.pipeline = pipeline }
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
            let failure: CaptureFailure?
            if case .stopFailureWithMedia(let value) = behavior {
                failure = value
            } else {
                failure = nil
            }
            return VideoCapturePipelineStopResult(
                mediaURL: outputURL,
                failure: failure,
                ingress: MediaIngressSnapshot()
            )
        }
        return VideoCapturePipelineStopResult(
            mediaURL: nil,
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
