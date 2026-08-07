import Foundation
import RecordCapture
import RecordCore
import RecordMedia

struct VideoCapturePipelineStopResult: Sendable {
    let artifacts: FinalizedSegmentArtifacts?
    let failure: CaptureFailure?
    let ingress: MediaIngressSnapshot

    var mediaURL: URL? { artifacts?[.screen] }
}

protocol VideoCapturePipeline: AnyObject, Sendable {
    func start() async throws
    func stop() async -> VideoCapturePipelineStopResult
}

protocol VideoCapturePipelineBuilding: Sendable {
    func makePipeline(
        configuration: CaptureConfiguration,
        outputURL: URL,
        onEvent: @escaping @Sendable (ScreenCaptureEvent) -> Void
    ) async throws -> any VideoCapturePipeline
}

struct ScreenCaptureVideoPipelineBuilder: VideoCapturePipelineBuilding {
    func makePipeline(
        configuration: CaptureConfiguration,
        outputURL: URL,
        onEvent: @escaping @Sendable (ScreenCaptureEvent) -> Void
    ) async throws -> any VideoCapturePipeline {
        let plan = try SegmentWriterPlan(configuration: configuration)
        let output = try SegmentOutputSet(
            screenURL: outputURL,
            includesSystemAudio: plan.includesSystemAudio,
            includesMicrophone: plan.includesMicrophone
        )
        let writer = try AVAssetSegmentWriter(plan: plan, output: output)
        let sink = BoundedScreenCaptureSink(
            configuration: try MediaIngressConfiguration(),
            processor: writer,
            onFailure: { onEvent(.failed($0)) }
        )
        let capture = try await ScreenCaptureKitStreamBuilder().prepare(
            configuration: configuration,
            sink: sink,
            onEvent: onEvent
        )
        return ScreenCaptureVideoPipeline(capture: capture, sink: sink, writer: writer)
    }
}

private actor ScreenCaptureVideoPipeline: VideoCapturePipeline {
    private let capture: ScreenCaptureSession
    private let sink: BoundedScreenCaptureSink
    private let writer: AVAssetSegmentWriter
    private var stopped: VideoCapturePipelineStopResult?

    init(
        capture: ScreenCaptureSession,
        sink: BoundedScreenCaptureSink,
        writer: AVAssetSegmentWriter
    ) {
        self.capture = capture
        self.sink = sink
        self.writer = writer
    }

    func start() async throws {
        try await capture.start()
    }

    func stop() async -> VideoCapturePipelineStopResult {
        if let stopped { return stopped }

        var failure: CaptureFailure?
        do {
            try await capture.stop()
        } catch {
            failure = Self.failure(for: error)
        }
        do {
            try await sink.finish()
        } catch {
            failure = failure ?? Self.failure(for: error)
        }

        var artifacts: FinalizedSegmentArtifacts?
        do {
            if case .finalized(let finalized) = try await writer.finish() {
                artifacts = finalized
            }
        } catch {
            failure = failure ?? Self.failure(for: error)
        }

        let result = VideoCapturePipelineStopResult(
            artifacts: artifacts,
            failure: failure,
            ingress: sink.snapshot()
        )
        stopped = result
        return result
    }

    private static func failure(for error: Error) -> CaptureFailure {
        if case .captureFailed(let failure) = error as? ScreenCaptureAdapterError {
            return failure
        }
        if case .processingFailed(let failure) = error as? MediaIngressError {
            return failure
        }
        if case .writingFailed(let failure) = error as? SegmentWriterError {
            return failure
        }
        return CaptureFailure(
            code: .internalFailure,
            summary: "video capture could not be finalized"
        )
    }
}

struct VideoRecordingOutcome: Sendable {
    let sessionDirectory: URL
    let mediaURL: URL?
    let state: SessionManifest.State
    let ingress: MediaIngressSnapshot
}

actor VideoRecordingSession {
    enum SessionError: Error, Equatable {
        case captureFailed(CaptureFailure)
        case noMediaSamples
    }

    nonisolated let id: UUID
    nonisolated let dir: URL
    nonisolated let startedAt: Date

    private let pipelineBuilder: any VideoCapturePipelineBuilding
    private let eventHandler: @Sendable (ScreenCaptureEvent) -> Void
    private var manifest: SessionManifest
    private var stateMachine = CaptureStateMachine()
    private var pipeline: (any VideoCapturePipeline)?
    private var terminalFailure: CaptureFailure?
    private var outcome: VideoRecordingOutcome?

    init(
        root: URL,
        startedAt: Date = Date(),
        id: UUID = UUID(),
        pipelineBuilder: any VideoCapturePipelineBuilding = ScreenCaptureVideoPipelineBuilder(),
        eventHandler: @escaping @Sendable (ScreenCaptureEvent) -> Void
    ) throws {
        self.id = id
        self.startedAt = startedAt
        self.pipelineBuilder = pipelineBuilder
        self.eventHandler = eventHandler
        dir = try SessionFolderAllocator.createDirectory(under: root, startedAt: startedAt)
        manifest = SessionManifest(
            id: id,
            ownerProcessIdentifier: ProcessInfo.processInfo.processIdentifier,
            startedAt: startedAt,
            tracks: Self.expectedTracks
        )
        try manifest.write(to: dir)
    }

    func start(configuration: CaptureConfiguration) async throws {
        _ = try stateMachine.handle(.start(sessionID: id, configuration: configuration))
        do {
            let pipeline = try await pipelineBuilder.makePipeline(
                configuration: configuration,
                outputURL: dir.appendingPathComponent("recording.mov"),
                onEvent: { [weak self] event in
                    Task { await self?.receive(event) }
                }
            )
            self.pipeline = pipeline
            try await pipeline.start()
            if let terminalFailure {
                throw SessionError.captureFailed(terminalFailure)
            }
            _ = try stateMachine.handle(.prepared)
        } catch {
            let failure = Self.failure(for: error)
            terminalFailure = terminalFailure ?? failure
            if case .failed = stateMachine.state {
                // The stream callback already transitioned the lifecycle.
            } else {
                _ = try? stateMachine.handle(.fail(failure))
            }
            let stopped = await pipeline?.stop()
            try markFailed(artifacts: stopped?.artifacts, at: Date())
            throw SessionError.captureFailed(failure)
        }
    }

    func stop(endedAt: Date = Date()) async throws -> VideoRecordingOutcome {
        if let outcome { return outcome }
        if case .failed = stateMachine.state {
            // Cleanup still runs below so recoverable media is retained.
        } else {
            _ = try stateMachine.handle(.stop)
        }

        guard let pipeline else {
            let failure = CaptureFailure(
                code: .internalFailure,
                summary: "video capture was not prepared"
            )
            try markFailed(artifacts: nil, at: endedAt)
            throw SessionError.captureFailed(failure)
        }

        let stopped = await pipeline.stop()
        let failure = terminalFailure ?? stopped.failure
        guard let mediaURL = stopped.mediaURL else {
            let resolvedFailure =
                failure
                ?? CaptureFailure(code: .writerFailed, summary: "no video samples were captured")
            terminalFailure = resolvedFailure
            try markFailed(artifacts: nil, at: endedAt)
            throw failure == nil
                ? SessionError.noMediaSamples
                : SessionError.captureFailed(resolvedFailure)
        }

        if let failure {
            terminalFailure = failure
            try markFailed(artifacts: stopped.artifacts, at: endedAt)
        } else {
            let tracks = Self.manifestTracks(from: stopped.artifacts)
            manifest = try manifest.finalized(at: endedAt, tracks: tracks)
            try manifest.write(to: dir)
            _ = try stateMachine.handle(.stopped)
        }

        let result = VideoRecordingOutcome(
            sessionDirectory: dir,
            mediaURL: mediaURL,
            state: manifest.state,
            ingress: stopped.ingress
        )
        outcome = result
        return result
    }

    private func receive(_ event: ScreenCaptureEvent) {
        if case .failed(let failure) = event {
            terminalFailure = terminalFailure ?? failure
            if case .failed = stateMachine.state {
                // Report only once, but always forward the original event.
            } else {
                _ = try? stateMachine.handle(.fail(failure))
                try? markFailed(artifacts: nil, at: Date())
            }
        }
        eventHandler(event)
    }

    private func markFailed(
        artifacts: FinalizedSegmentArtifacts?,
        at endedAt: Date
    ) throws {
        manifest.state = .failed
        manifest.endedAt = max(endedAt, startedAt)
        manifest.tracks = Self.manifestTracks(from: artifacts)
        try manifest.write(to: dir)
    }

    private static let expectedTracks: [SessionManifest.Track] = [
        .init(kind: .screen, filename: "recording.mov"),
        .init(kind: .systemAudio, filename: "system.caf", speaker: "them"),
        .init(kind: .microphone, filename: "mic.caf", speaker: "me"),
    ]

    private static func manifestTracks(
        from artifacts: FinalizedSegmentArtifacts?
    ) -> [SessionManifest.Track] {
        guard let artifacts else { return expectedTracks }
        return ScreenCaptureSampleKind.allCases.compactMap { kind in
            guard let url = artifacts[kind] else { return nil }
            let manifestKind: SessionManifest.TrackKind
            let speaker: String?
            switch kind {
            case .screen:
                manifestKind = .screen
                speaker = nil
            case .systemAudio:
                manifestKind = .systemAudio
                speaker = "them"
            case .microphone:
                manifestKind = .microphone
                speaker = "me"
            }
            return SessionManifest.Track(
                kind: manifestKind,
                filename: url.lastPathComponent,
                speaker: speaker,
                startOffsetMilliseconds: artifacts.startOffsetMilliseconds[kind] ?? 0
            )
        }
    }

    private static func failure(for error: Error) -> CaptureFailure {
        if case .captureFailed(let failure) = error as? ScreenCaptureAdapterError {
            return failure
        }
        if case .captureFailed(let failure) = error as? SessionError {
            return failure
        }
        return CaptureFailure(
            code: .internalFailure,
            summary: "video capture could not start"
        )
    }
}
