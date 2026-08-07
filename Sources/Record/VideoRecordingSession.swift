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

struct VideoCaptureOutputURLs: Equatable, Sendable {
    let files: [ScreenCaptureSampleKind: URL]

    init(
        directory: URL,
        segmentIndex: Int,
        configuration: CaptureConfiguration
    ) {
        precondition(segmentIndex > 0)
        let stem = String(format: "segment-%04d", segmentIndex)
        var files: [ScreenCaptureSampleKind: URL] = [
            .screen: directory.appendingPathComponent("\(stem).mov")
        ]
        if configuration.audio.includeSystemAudio {
            files[.systemAudio] = directory.appendingPathComponent("\(stem)-system.caf")
        }
        if configuration.audio.includeMicrophone {
            files[.microphone] = directory.appendingPathComponent("\(stem)-mic.caf")
        }
        self.files = files
    }
}

protocol VideoCapturePipeline: AnyObject, Sendable {
    func start() async throws
    func stop() async -> VideoCapturePipelineStopResult
}

protocol VideoCapturePipelineBuilding: Sendable {
    func makePipeline(
        configuration: CaptureConfiguration,
        selection: SystemScreenCaptureSelection?,
        outputURLs: VideoCaptureOutputURLs,
        onEvent: @escaping @Sendable (ScreenCaptureEvent) -> Void
    ) async throws -> any VideoCapturePipeline
}

/// Rebuilds a fresh ScreenCaptureKit stream after failures which macOS can
/// report while its shareable-content and audio services are still settling.
/// Permission and writer failures require user action or would risk clobbering
/// media, so they are never retried here.
struct VideoCaptureStartupRetryPolicy: Sendable {
    static let standard = Self(delays: [.milliseconds(250), .milliseconds(750)])

    let delays: [Duration]

    func delay(
        after failure: CaptureFailure,
        failedAttempt: Int,
        hasPreservedArtifacts: Bool
    ) -> Duration? {
        guard !hasPreservedArtifacts,
            failedAttempt > 0,
            failedAttempt <= delays.count
        else { return nil }

        switch failure.code {
        case .internalFailure, .sourceUnavailable, .deviceDisconnected:
            return delays[failedAttempt - 1]
        case .permissionDenied, .encoderFailed, .writerFailed:
            return nil
        }
    }
}

struct ScreenCaptureVideoPipelineBuilder: VideoCapturePipelineBuilding {
    func makePipeline(
        configuration: CaptureConfiguration,
        selection: SystemScreenCaptureSelection?,
        outputURLs: VideoCaptureOutputURLs,
        onEvent: @escaping @Sendable (ScreenCaptureEvent) -> Void
    ) async throws -> any VideoCapturePipeline {
        let plan = try SegmentWriterPlan(configuration: configuration)
        let output = try SegmentOutputSet(finalURLs: outputURLs.files)
        let writer = try AVAssetSegmentWriter(plan: plan, output: output)
        let healthStartedAt = Date()
        let sink = BoundedScreenCaptureSink(
            configuration: try MediaIngressConfiguration(),
            processor: writer,
            onFailure: { onEvent(.failed($0)) },
            onHealth: { kind, code, severity in
                onEvent(
                    .health(
                        .init(
                            track: kind.captureHealthTrack,
                            code: code,
                            severity: severity,
                            occurredAtMilliseconds: max(
                                0,
                                Int(Date().timeIntervalSince(healthStartedAt) * 1_000)
                            )
                        )
                    )
                )
            }
        )
        let streamBuilder = ScreenCaptureKitStreamBuilder()
        let capture: ScreenCaptureSession
        if let selection {
            capture = try await streamBuilder.prepare(
                selection: selection,
                configuration: configuration,
                sink: sink,
                onEvent: onEvent
            )
        } else {
            capture = try await streamBuilder.prepare(
                configuration: configuration,
                sink: sink,
                onEvent: onEvent
            )
        }
        return ScreenCaptureVideoPipeline(capture: capture, sink: sink, writer: writer)
    }
}

protocol VideoSegmentCombining: Sendable {
    func combine(
        _ segments: [CaptureSegmentArtifactSet],
        in directory: URL
    ) async throws -> FinalizedSegmentArtifacts
}

struct AVVideoSegmentCombiner: VideoSegmentCombining {
    func combine(
        _ segments: [CaptureSegmentArtifactSet],
        in directory: URL
    ) async throws -> FinalizedSegmentArtifacts {
        guard let first = segments.first else {
            throw AVAssetSegmentConcatenator.ConcatenationError.noSegments
        }
        var finalURLs: [ScreenCaptureSampleKind: URL] = [
            .screen: directory.appendingPathComponent("recording.mov")
        ]
        if first.artifacts[.systemAudio] != nil {
            finalURLs[.systemAudio] = directory.appendingPathComponent("system.caf")
        }
        if first.artifacts[.microphone] != nil {
            finalURLs[.microphone] = directory.appendingPathComponent("mic.caf")
        }
        return try await AVAssetSegmentConcatenator().concatenate(
            segments,
            to: finalURLs
        )
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
    private let segmentCombiner: any VideoSegmentCombining
    private let startupRetryPolicy: VideoCaptureStartupRetryPolicy
    private let eventHandler: @Sendable (ScreenCaptureEvent) -> Void
    private var manifest: SessionManifest
    private var stateMachine = CaptureStateMachine()
    private var pipeline: (any VideoCapturePipeline)?
    private var terminalFailure: CaptureFailure?
    private var outcome: VideoRecordingOutcome?
    private var activePipelineID: UUID?
    private var healthEvents: [CaptureHealthEvent] = []
    private var expectedCaptureKinds: Set<ScreenCaptureSampleKind> = Set(
        ScreenCaptureSampleKind.allCases
    )
    private var configuration: CaptureConfiguration?
    private var selection: SystemScreenCaptureSelection?
    private var activeSegmentIndex: Int?
    private var completedSegments: [CaptureSegmentArtifactSet] = []
    private var ingress = MediaIngressSnapshot()
    private var rotationInProgress = false
    private var rotationWaiters: [CheckedContinuation<Void, Never>] = []

    init(
        root: URL,
        startedAt: Date = Date(),
        id: UUID = UUID(),
        pipelineBuilder: any VideoCapturePipelineBuilding = ScreenCaptureVideoPipelineBuilder(),
        segmentCombiner: any VideoSegmentCombining = AVVideoSegmentCombiner(),
        startupRetryPolicy: VideoCaptureStartupRetryPolicy = .standard,
        eventHandler: @escaping @Sendable (ScreenCaptureEvent) -> Void
    ) throws {
        self.id = id
        self.startedAt = startedAt
        self.pipelineBuilder = pipelineBuilder
        self.segmentCombiner = segmentCombiner
        self.startupRetryPolicy = startupRetryPolicy
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

    func start(
        configuration: CaptureConfiguration,
        selection: SystemScreenCaptureSelection? = nil,
        at date: Date = Date()
    ) async throws {
        self.configuration = configuration
        self.selection = selection
        expectedCaptureKinds = [.screen]
        if configuration.audio.includeSystemAudio { expectedCaptureKinds.insert(.systemAudio) }
        if configuration.audio.includeMicrophone { expectedCaptureKinds.insert(.microphone) }
        _ = try stateMachine.handle(.start(sessionID: id, configuration: configuration))
        do {
            try beginManifestSegment(index: 1, event: .started, at: date)
            try await startPipeline(
                segmentIndex: 1,
                configuration: configuration,
                selection: selection
            )
            _ = try stateMachine.handle(.prepared)
        } catch {
            if case .failed = stateMachine.state {
                // `startPipeline` already recorded the classified failure.
            } else {
                try? failCapture(with: Self.failure(for: error), at: date)
            }
            throw error
        }
    }

    func pause(at date: Date = Date()) async throws {
        guard !rotationInProgress else { return }
        rotationInProgress = true
        defer { finishRotation() }
        let effects = try stateMachine.handle(.pause)
        guard effects.contains(.finishSegment(sessionID: id)) else { return }
        do {
            _ = try await finishActiveSegment(at: date)
            appendCaptureEvent(.paused, at: date, segmentIndex: completedSegments.last?.index)
            try manifest.write(to: dir)
        } catch {
            try failCapture(with: Self.failure(for: error), at: date)
            throw error
        }
    }

    func resume(at date: Date = Date()) async throws {
        guard !rotationInProgress else { return }
        rotationInProgress = true
        defer { finishRotation() }
        let effects = try stateMachine.handle(.resume)
        guard effects.contains(.beginSegment(sessionID: id)) else { return }
        guard let configuration else {
            let failure = CaptureFailure(
                code: .internalFailure,
                summary: "video capture configuration was unavailable"
            )
            try failCapture(with: failure, at: date)
            throw SessionError.captureFailed(failure)
        }
        let nextIndex = completedSegments.count + 1
        do {
            try beginManifestSegment(index: nextIndex, event: .resumed, at: date)
            try await startPipeline(
                segmentIndex: nextIndex,
                configuration: configuration,
                selection: selection
            )
        } catch {
            if case .failed = stateMachine.state {
                // `startPipeline` already recorded the classified failure.
            } else {
                try? failCapture(with: Self.failure(for: error), at: date)
            }
            throw error
        }
    }

    func isPaused() -> Bool {
        if case .paused = stateMachine.state { return true }
        return false
    }

    private func startPipeline(
        segmentIndex: Int,
        configuration: CaptureConfiguration,
        selection: SystemScreenCaptureSelection?
    ) async throws {
        var failedAttempt = 0
        while true {
            let pipelineID = UUID()
            activePipelineID = pipelineID
            activeSegmentIndex = segmentIndex
            terminalFailure = nil
            do {
                let pipeline = try await pipelineBuilder.makePipeline(
                    configuration: configuration,
                    selection: selection,
                    outputURLs: VideoCaptureOutputURLs(
                        directory: dir,
                        segmentIndex: segmentIndex,
                        configuration: configuration
                    ),
                    onEvent: { [weak self] event in
                        Task { await self?.receive(event, from: pipelineID) }
                    }
                )
                self.pipeline = pipeline
                try await pipeline.start()
                if let terminalFailure {
                    throw SessionError.captureFailed(terminalFailure)
                }
                return
            } catch {
                failedAttempt += 1
                let failure = terminalFailure ?? Self.failure(for: error)
                let stopped = await pipeline?.stop()
                if let delay = startupRetryPolicy.delay(
                    after: failure,
                    failedAttempt: failedAttempt,
                    hasPreservedArtifacts: stopped?.artifacts != nil
                ) {
                    FileHandle.standardError.write(
                        Data(
                            "screen capture startup retry \(failedAttempt) after \(failure.summary)\n"
                                .utf8
                        )
                    )
                    self.pipeline = nil
                    activePipelineID = nil
                    try await Task.sleep(for: delay)
                    continue
                }

                terminalFailure = failure
                if let stopped {
                    ingress = ingress.merging(stopped.ingress)
                    if let artifacts = stopped.artifacts {
                        try? recordCompletedSegment(
                            index: segmentIndex,
                            artifacts: artifacts,
                            endedAt: Date()
                        )
                    }
                }
                self.pipeline = nil
                activePipelineID = nil
                activeSegmentIndex = nil
                _ = try? stateMachine.handle(.fail(failure))
                try markFailed(failure: failure, at: Date())
                throw SessionError.captureFailed(failure)
            }
        }
    }

    func stop(endedAt: Date = Date()) async throws -> VideoRecordingOutcome {
        await waitForRotation()
        if let outcome { return outcome }
        let wasFailed: Bool
        if case .failed = stateMachine.state {
            wasFailed = true
        } else {
            wasFailed = false
            _ = try stateMachine.handle(.stop)
        }

        if pipeline != nil {
            do {
                _ = try await finishActiveSegment(at: endedAt)
            } catch {
                let failure = terminalFailure ?? Self.failure(for: error)
                try failCapture(with: failure, at: endedAt)
                if completedSegments.isEmpty { throw error }
            }
        }

        guard !completedSegments.isEmpty else {
            let failure =
                terminalFailure
                ?? CaptureFailure(code: .writerFailed, summary: "no video samples were captured")
            try failCapture(with: failure, at: endedAt)
            throw terminalFailure == nil
                ? SessionError.noMediaSamples
                : SessionError.captureFailed(failure)
        }

        if wasFailed || terminalFailure != nil {
            let failure =
                terminalFailure
                ?? CaptureFailure(code: .internalFailure, summary: "video capture stopped early")
            try markFailed(failure: failure, at: endedAt)
            let failedResult = VideoRecordingOutcome(
                sessionDirectory: dir,
                mediaURL: completedSegments.last?.artifacts[.screen],
                state: .failed,
                ingress: ingress
            )
            outcome = failedResult
            return failedResult
        }

        appendCaptureEvent(.stopped, at: endedAt, segmentIndex: completedSegments.last?.index)
        try manifest.write(to: dir)
        let artifacts: FinalizedSegmentArtifacts
        do {
            artifacts = try await segmentCombiner.combine(completedSegments, in: dir)
        } catch {
            let failure = CaptureFailure(
                code: .writerFailed,
                summary: "recording segments could not be assembled"
            )
            try failCapture(with: failure, at: endedAt)
            throw SessionError.captureFailed(failure)
        }
        manifest.healthEvents = healthEvents.isEmpty ? nil : healthEvents
        manifest.captureSegments = nil
        manifest = try manifest.finalized(
            at: endedAt,
            tracks: Self.manifestTracks(from: artifacts)
        )
        try manifest.write(to: dir)
        _ = try stateMachine.handle(.stopped)

        let result = VideoRecordingOutcome(
            sessionDirectory: dir,
            mediaURL: artifacts[.screen],
            state: manifest.state,
            ingress: ingress
        )
        outcome = result
        return result
    }

    private func finishActiveSegment(at date: Date) async throws -> VideoCapturePipelineStopResult {
        guard let pipeline, let segmentIndex = activeSegmentIndex else {
            let failure = CaptureFailure(
                code: .internalFailure,
                summary: "video capture segment was not active"
            )
            throw SessionError.captureFailed(failure)
        }
        activePipelineID = nil
        self.pipeline = nil
        activeSegmentIndex = nil
        let stopped = await pipeline.stop()
        ingress = ingress.merging(stopped.ingress)
        recordMissingCallbacks(from: stopped.ingress, at: date)
        if let failure = terminalFailure ?? stopped.failure {
            terminalFailure = failure
            if let artifacts = stopped.artifacts {
                try recordCompletedSegment(
                    index: segmentIndex,
                    artifacts: artifacts,
                    endedAt: date
                )
            }
            throw SessionError.captureFailed(failure)
        }
        guard let artifacts = stopped.artifacts, artifacts[.screen] != nil else {
            throw SessionError.noMediaSamples
        }
        try recordCompletedSegment(
            index: segmentIndex,
            artifacts: artifacts,
            endedAt: date
        )
        return stopped
    }

    private func beginManifestSegment(
        index: Int,
        event: SessionManifest.CaptureEvent.Kind,
        at date: Date
    ) throws {
        guard let configuration else {
            throw SessionError.captureFailed(
                CaptureFailure(
                    code: .internalFailure,
                    summary: "video capture configuration was unavailable"
                )
            )
        }
        let output = VideoCaptureOutputURLs(
            directory: dir,
            segmentIndex: index,
            configuration: configuration
        )
        let tracks = Self.manifestTracks(
            from: FinalizedSegmentArtifacts(files: output.files)
        )
        manifest.captureSegments =
            (manifest.captureSegments ?? []) + [
                .init(
                    index: index,
                    startedAtMilliseconds: milliseconds(sinceStart: date),
                    tracks: tracks
                )
            ]
        appendCaptureEvent(event, at: date, segmentIndex: index)
        try manifest.write(to: dir)
    }

    private func recordCompletedSegment(
        index: Int,
        artifacts: FinalizedSegmentArtifacts,
        endedAt date: Date
    ) throws {
        guard
            let segmentOffset = manifest.captureSegments?.firstIndex(where: {
                $0.index == index
            })
        else {
            throw SessionError.captureFailed(
                CaptureFailure(code: .internalFailure, summary: "capture segment was untracked")
            )
        }
        manifest.captureSegments?[segmentOffset].tracks = Self.manifestTracks(from: artifacts)
        manifest.captureSegments?[segmentOffset].endedAtMilliseconds = milliseconds(
            sinceStart: date
        )
        completedSegments.append(.init(index: index, artifacts: artifacts))
        try manifest.write(to: dir)
    }

    private func appendCaptureEvent(
        _ kind: SessionManifest.CaptureEvent.Kind,
        at date: Date,
        segmentIndex: Int?
    ) {
        manifest.captureEvents =
            (manifest.captureEvents ?? []) + [
                .init(
                    kind: kind,
                    occurredAtMilliseconds: milliseconds(sinceStart: date),
                    segmentIndex: segmentIndex
                )
            ]
    }

    private func milliseconds(sinceStart date: Date) -> Int {
        max(0, Int(date.timeIntervalSince(startedAt) * 1_000))
    }

    private func failCapture(with failure: CaptureFailure, at date: Date) throws {
        terminalFailure = terminalFailure ?? failure
        _ = try? stateMachine.handle(.fail(failure))
        try markFailed(failure: failure, at: date)
    }

    private func waitForRotation() async {
        while rotationInProgress {
            await withCheckedContinuation { continuation in
                rotationWaiters.append(continuation)
            }
        }
    }

    private func finishRotation() {
        rotationInProgress = false
        let waiters = rotationWaiters
        rotationWaiters.removeAll(keepingCapacity: false)
        waiters.forEach { $0.resume() }
    }

    private func receive(_ event: ScreenCaptureEvent, from pipelineID: UUID) {
        guard pipelineID == activePipelineID else { return }
        var forwardedEvent = event
        if case .health(let health) = event {
            let normalizedHealth = CaptureHealthEvent(
                track: health.track,
                code: health.code,
                severity: health.severity,
                occurredAtMilliseconds: max(
                    0,
                    Int(Date().timeIntervalSince(startedAt) * 1_000)
                ),
                durationMilliseconds: health.durationMilliseconds
            )
            healthEvents.append(normalizedHealth)
            manifest.healthEvents = healthEvents
            try? manifest.write(to: dir)
            forwardedEvent = .health(normalizedHealth)
        } else if case .failed(let failure) = event {
            terminalFailure = terminalFailure ?? failure
            if case .preparing = stateMachine.state {
                // `start(configuration:)` owns bounded retry and final error
                // reporting while a stream is still being prepared.
                return
            }
            if case .failed = stateMachine.state {
                // Report only once, but always forward the original event.
            } else {
                _ = try? stateMachine.handle(.fail(failure))
                try? markFailed(failure: failure, at: Date())
            }
        }
        eventHandler(forwardedEvent)
    }

    private func recordMissingCallbacks(from ingress: MediaIngressSnapshot, at date: Date) {
        for kind in ScreenCaptureSampleKind.allCases
        where expectedCaptureKinds.contains(kind) && ingress[kind].received == 0 {
            let event = CaptureHealthEvent(
                track: kind.captureHealthTrack,
                code: .missingCallbacks,
                severity: .failed,
                occurredAtMilliseconds: max(0, Int(date.timeIntervalSince(startedAt) * 1_000))
            )
            healthEvents.append(event)
            eventHandler(.health(event))
        }
    }

    private func markFailed(
        failure: CaptureFailure,
        at endedAt: Date
    ) throws {
        manifest.state = .failed
        manifest.endedAt = max(endedAt, startedAt)
        manifest.failure = failure
        manifest.healthEvents = healthEvents.isEmpty ? nil : healthEvents
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

private extension ScreenCaptureSampleKind {
    var captureHealthTrack: CaptureHealthEvent.Track {
        switch self {
        case .screen: .screen
        case .systemAudio: .systemAudio
        case .microphone: .microphone
        }
    }
}
