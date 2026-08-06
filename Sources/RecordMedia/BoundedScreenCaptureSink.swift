import CoreMedia
import Dispatch
import Foundation
import RecordCapture
import RecordCore

public struct MediaIngressConfiguration: Equatable, Sendable {
    public static let allowedScreenCapacity = 1...8
    public static let allowedAudioCapacity = 1...128

    public let screenCapacity: Int
    public let systemAudioCapacity: Int
    public let microphoneCapacity: Int

    public init(
        screenCapacity: Int = 3,
        systemAudioCapacity: Int = 32,
        microphoneCapacity: Int = 32
    ) throws {
        guard Self.allowedScreenCapacity.contains(screenCapacity) else {
            throw MediaIngressError.invalidCapacity(kind: .screen, value: screenCapacity)
        }
        guard Self.allowedAudioCapacity.contains(systemAudioCapacity) else {
            throw MediaIngressError.invalidCapacity(
                kind: .systemAudio,
                value: systemAudioCapacity
            )
        }
        guard Self.allowedAudioCapacity.contains(microphoneCapacity) else {
            throw MediaIngressError.invalidCapacity(kind: .microphone, value: microphoneCapacity)
        }
        self.screenCapacity = screenCapacity
        self.systemAudioCapacity = systemAudioCapacity
        self.microphoneCapacity = microphoneCapacity
    }

    public func capacity(for kind: ScreenCaptureSampleKind) -> Int {
        switch kind {
        case .screen: screenCapacity
        case .systemAudio: systemAudioCapacity
        case .microphone: microphoneCapacity
        }
    }
}

public struct MediaTrackIngressSnapshot: Equatable, Sendable {
    public fileprivate(set) var received = 0
    public fileprivate(set) var processed = 0
    public fileprivate(set) var droppedForBackpressure = 0
    public fileprivate(set) var discardedAfterFailure = 0
    public fileprivate(set) var rejectedAfterFinish = 0
    public fileprivate(set) var pending = 0
    public fileprivate(set) var highWatermark = 0
}

public struct MediaIngressSnapshot: Equatable, Sendable {
    public let tracks: [ScreenCaptureSampleKind: MediaTrackIngressSnapshot]

    public subscript(kind: ScreenCaptureSampleKind) -> MediaTrackIngressSnapshot {
        tracks[kind] ?? MediaTrackIngressSnapshot()
    }
}

public enum MediaIngressError: Error, Equatable, Sendable {
    case invalidCapacity(kind: ScreenCaptureSampleKind, value: Int)
    case processingFailed(CaptureFailure)
}

public struct MediaSampleProcessingFailure: Error, Equatable, Sendable {
    public let failure: CaptureFailure

    public init(_ failure: CaptureFailure) {
        self.failure = failure
    }
}

public protocol MediaSampleProcessing: AnyObject, Sendable {
    /// Runs on the media worker, never on a ScreenCaptureKit callback queue.
    func process(_ sample: ScreenCaptureSample) throws
}

private final class MediaTrackIngressState {
    var buffer: BoundedRingBuffer<ScreenCaptureSample>
    var snapshot = MediaTrackIngressSnapshot()

    init(capacity: Int) {
        buffer = BoundedRingBuffer(capacity: capacity)
    }
}

/// A fixed-capacity, nonblocking boundary between ScreenCaptureKit and media
/// processing. On overflow it evicts the oldest queued sample for that track,
/// keeping latency bounded while preserving the newest capture state.
public final class BoundedScreenCaptureSink: ScreenCaptureSampleSink, @unchecked Sendable {
    private let processor: any MediaSampleProcessing
    private let onFailure: @Sendable (CaptureFailure) -> Void
    private let worker: DispatchQueue
    private let lock = NSLock()

    private var tracks: [ScreenCaptureSampleKind: MediaTrackIngressState]
    private var drainScheduled = false
    private var sealed = false
    private var terminalFailure: CaptureFailure?
    private var finishWaiters: [CheckedContinuation<Void, any Error>] = []

    public init(
        configuration: MediaIngressConfiguration,
        processor: any MediaSampleProcessing,
        worker: DispatchQueue = DispatchQueue(
            label: "com.aindaco.record.media.ingress",
            qos: .userInitiated,
            autoreleaseFrequency: .workItem
        ),
        onFailure: @escaping @Sendable (CaptureFailure) -> Void = { _ in }
    ) {
        self.processor = processor
        self.worker = worker
        self.onFailure = onFailure
        tracks = Dictionary(
            uniqueKeysWithValues: ScreenCaptureSampleKind.allCases.map {
                ($0, MediaTrackIngressState(capacity: configuration.capacity(for: $0)))
            }
        )
    }

    public func consume(_ sample: ScreenCaptureSample) {
        var shouldScheduleDrain = false

        lock.lock()
        guard let track = tracks[sample.kind] else {
            lock.unlock()
            assertionFailure("Missing media ingress state for \(sample.kind)")
            return
        }
        track.snapshot.received += 1
        guard !sealed else {
            track.snapshot.rejectedAfterFinish += 1
            lock.unlock()
            return
        }

        if track.buffer.appendDroppingOldest(sample) != nil {
            track.snapshot.droppedForBackpressure += 1
        }
        track.snapshot.pending = track.buffer.count
        track.snapshot.highWatermark = max(
            track.snapshot.highWatermark,
            track.buffer.count
        )

        if !drainScheduled {
            drainScheduled = true
            shouldScheduleDrain = true
        }
        lock.unlock()

        if shouldScheduleDrain {
            worker.async { [self] in drain() }
        }
    }

    public func snapshot() -> MediaIngressSnapshot {
        lock.lock()
        let snapshot = MediaIngressSnapshot(
            tracks: Dictionary(uniqueKeysWithValues: tracks.map { ($0.key, $0.value.snapshot) })
        )
        lock.unlock()
        return snapshot
    }

    /// Seals the ingress, drains accepted samples, and waits for the processor.
    /// Repeated and concurrent calls receive the same terminal result.
    public func finish() async throws {
        try await withCheckedThrowingContinuation { continuation in
            var immediateResult: Result<Void, any Error>?
            var shouldScheduleDrain = false

            lock.lock()
            sealed = true
            if let terminalFailure {
                immediateResult = .failure(MediaIngressError.processingFailed(terminalFailure))
            } else if !drainScheduled
                && tracks.values.allSatisfy({ $0.buffer.count == 0 })
            {
                immediateResult = .success(())
            } else {
                finishWaiters.append(continuation)
                if !drainScheduled {
                    drainScheduled = true
                    shouldScheduleDrain = true
                }
            }
            lock.unlock()

            if let immediateResult {
                continuation.resume(with: immediateResult)
            } else if shouldScheduleDrain {
                worker.async { [self] in drain() }
            }
        }
    }

    private func drain() {
        while true {
            lock.lock()
            guard let kind = nextKind(), let track = tracks[kind],
                let sample = track.buffer.popFirst()
            else {
                drainScheduled = false
                let waiters = sealed ? takeFinishWaiters() : []
                lock.unlock()
                resume(waiters, with: .success(()))
                return
            }
            track.snapshot.pending = track.buffer.count
            lock.unlock()

            do {
                try processor.process(sample)
                lock.lock()
                track.snapshot.processed += 1
                lock.unlock()
            } catch {
                fail(error, failedKind: kind)
                return
            }
        }
    }

    private func nextKind() -> ScreenCaptureSampleKind? {
        ScreenCaptureSampleKind.allCases.reduce(nil) { selected, candidate in
            guard let candidateSample = tracks[candidate]?.buffer.first else { return selected }
            guard let selected,
                let selectedSample = tracks[selected]?.buffer.first
            else {
                return candidate
            }
            return CMTimeCompare(candidateSample.timestamp.time, selectedSample.timestamp.time) < 0
                ? candidate : selected
        }
    }

    private func fail(_ error: Error, failedKind: ScreenCaptureSampleKind) {
        let failure: CaptureFailure
        if let typed = error as? MediaSampleProcessingFailure {
            failure = typed.failure
        } else {
            failure = CaptureFailure(
                code: .writerFailed,
                summary: "media sample processing failed"
            )
        }

        lock.lock()
        sealed = true
        terminalFailure = failure
        drainScheduled = false
        tracks[failedKind]?.snapshot.discardedAfterFailure += 1
        for kind in ScreenCaptureSampleKind.allCases {
            guard let track = tracks[kind] else { continue }
            track.snapshot.discardedAfterFailure += track.buffer.removeAll()
            track.snapshot.pending = 0
        }
        let waiters = takeFinishWaiters()
        lock.unlock()

        onFailure(failure)
        resume(waiters, with: .failure(MediaIngressError.processingFailed(failure)))
    }

    private func takeFinishWaiters() -> [CheckedContinuation<Void, any Error>] {
        let waiters = finishWaiters
        finishWaiters.removeAll(keepingCapacity: false)
        return waiters
    }

    private func resume(
        _ waiters: [CheckedContinuation<Void, any Error>],
        with result: Result<Void, any Error>
    ) {
        for waiter in waiters {
            waiter.resume(with: result)
        }
    }
}
