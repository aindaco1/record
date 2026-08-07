import AVFoundation
import Foundation

/// Fixed-capacity handoff from real-time audio callbacks to one serial file
/// writer. Callback work is bounded to an owning buffer copy plus an O(1)
/// enqueue; codec and filesystem work never runs on the capture callback.
final class AudioFileWritePump: @unchecked Sendable {
    enum Event: Equatable, Sendable {
        case queuePressure
        case writeFailed
    }

    struct Snapshot: Equatable, Sendable {
        var receivedBuffers = 0
        var writtenBuffers = 0
        var droppedForBackpressure = 0
        var rejectedAfterFinish = 0
        var highWatermark = 0
        var writeFailed = false
        var paddedFrames: Int64 = 0
        var firstBufferAt: Date?
        var lastBufferAt: Date?
    }

    private enum WorkItem {
        case audio(AVAudioPCMBuffer)
        case silence(frames: Int64)
    }

    private struct Ring {
        let capacity: Int
        private var storage: [WorkItem?]
        private(set) var count = 0
        private var head = 0

        init(capacity: Int) {
            precondition(capacity > 0)
            self.capacity = capacity
            storage = Array(repeating: nil, count: capacity)
        }

        mutating func appendDroppingOldest(_ item: WorkItem) -> Bool {
            if count < capacity {
                storage[(head + count) % capacity] = item
                count += 1
                return false
            }
            storage[head] = item
            head = (head + 1) % capacity
            return true
        }

        mutating func popFirst() -> WorkItem? {
            guard count > 0 else { return nil }
            let buffer = storage[head]
            storage[head] = nil
            head = (head + 1) % capacity
            count -= 1
            return buffer
        }
    }

    private let lock = NSLock()
    private let worker: DispatchQueue
    private let onEvent: @Sendable (Event) -> Void
    private var file: AVAudioFile?
    private var pending: Ring
    private var state = Snapshot()
    private var drainScheduled = false
    private var sealed = false
    private var reportedQueuePressure = false
    private var reportedWriteFailure = false
    private var converter: AVAudioConverter?
    private var converterSourceFormat: AVAudioFormat?

    let processingFormat: AVAudioFormat

    init(
        file: AVAudioFile,
        capacity: Int = 32,
        worker: DispatchQueue = DispatchQueue(
            label: "com.aindaco.record.audio-file-writer",
            qos: .userInitiated,
            autoreleaseFrequency: .workItem
        ),
        onEvent: @escaping @Sendable (Event) -> Void = { _ in }
    ) {
        self.file = file
        processingFormat = file.processingFormat
        pending = Ring(capacity: capacity)
        self.worker = worker
        self.onEvent = onEvent
    }

    /// Copies the callback-owned buffer before returning. A failed allocation
    /// is treated as backpressure instead of retaining invalid callback memory.
    func enqueueCopy(of source: AVAudioPCMBuffer, capturedAt: Date = Date()) {
        guard let copy = Self.copy(source) else {
            report(.queuePressure)
            return
        }
        enqueueOwned(copy, capturedAt: capturedAt)
    }

    /// Accepts a buffer whose storage is already independently owned, such as
    /// AVAudioConverter output created for this handoff.
    func enqueueOwned(_ buffer: AVAudioPCMBuffer, capturedAt: Date = Date()) {
        var shouldSchedule = false
        var event: Event?

        lock.lock()
        state.receivedBuffers += 1
        guard !sealed else {
            state.rejectedAfterFinish += 1
            lock.unlock()
            return
        }
        if state.firstBufferAt == nil { state.firstBufferAt = capturedAt }
        state.lastBufferAt = capturedAt
        if pending.appendDroppingOldest(.audio(buffer)) {
            state.droppedForBackpressure += 1
            if !reportedQueuePressure {
                reportedQueuePressure = true
                event = .queuePressure
            }
        }
        state.highWatermark = max(state.highWatermark, pending.count)
        if !drainScheduled {
            drainScheduled = true
            shouldSchedule = true
        }
        lock.unlock()

        if let event { onEvent(event) }
        if shouldSchedule {
            worker.async { [self] in drain() }
        }
    }

    /// Preserves a monotonic recording timeline across a temporary route
    /// outage. The duration is one bounded queue item; zero buffers are
    /// allocated and written incrementally on the file worker.
    func enqueueSilence(durationMilliseconds: Int, capturedAt: Date = Date()) {
        guard durationMilliseconds > 0 else { return }
        let frames = Int64(
            (Double(durationMilliseconds) * processingFormat.sampleRate / 1_000).rounded()
        )
        guard frames > 0 else { return }

        var shouldSchedule = false
        var shouldReportPressure = false
        lock.lock()
        guard !sealed else {
            state.rejectedAfterFinish += 1
            lock.unlock()
            return
        }
        state.lastBufferAt = capturedAt
        if pending.appendDroppingOldest(.silence(frames: frames)) {
            state.droppedForBackpressure += 1
            if !reportedQueuePressure {
                reportedQueuePressure = true
                shouldReportPressure = true
            }
        }
        state.highWatermark = max(state.highWatermark, pending.count)
        if !drainScheduled {
            drainScheduled = true
            shouldSchedule = true
        }
        lock.unlock()

        if shouldReportPressure { onEvent(.queuePressure) }
        if shouldSchedule { worker.async { [self] in drain() } }
    }

    func snapshot() -> Snapshot {
        lock.withLock { state }
    }

    /// Seals input, drains every accepted buffer, and releases the file. The
    /// capture source must be stopped before calling this method.
    func finish() {
        lock.withLock { sealed = true }
        worker.sync {
            drain()
            file = nil
        }
    }

    private func drain() {
        while true {
            let item: WorkItem? = lock.withLock {
                guard let next = pending.popFirst() else {
                    drainScheduled = false
                    return nil
                }
                return next
            }
            guard let item else { return }

            do {
                switch item {
                case .audio(let buffer):
                    try file?.write(from: try normalized(buffer))
                    lock.withLock { state.writtenBuffers += 1 }
                case .silence(let frames):
                    try writeSilence(frames: frames)
                    lock.withLock { state.paddedFrames += frames }
                }
            } catch {
                var shouldReport = false
                lock.withLock {
                    state.writeFailed = true
                    if !reportedWriteFailure {
                        reportedWriteFailure = true
                        shouldReport = true
                    }
                }
                if shouldReport { onEvent(.writeFailed) }
            }
        }
    }

    private func normalized(_ source: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
        if source.format == processingFormat { return source }

        if converter == nil || converterSourceFormat != source.format {
            converter = AVAudioConverter(from: source.format, to: processingFormat)
            converter?.primeMethod = .none
            converterSourceFormat = source.format
        }
        guard let converter else {
            throw NSError(
                domain: "Record.AudioFileWritePump",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "audio format conversion is unavailable"]
            )
        }

        let ratio = processingFormat.sampleRate / source.format.sampleRate
        let capacity = AVAudioFrameCount(
            // Leave room for the converter's bounded resampling latency to
            // emerge on a later callback without clipping that output.
            max(1, ceil(Double(source.frameLength) * ratio) + 1_024)
        )
        guard let output = AVAudioPCMBuffer(
            pcmFormat: processingFormat,
            frameCapacity: capacity
        ) else {
            throw NSError(
                domain: "Record.AudioFileWritePump",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "audio conversion buffer allocation failed"]
            )
        }

        let input = ConverterInput(buffer: source)
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) {
            _, inputStatus in
            input.next(status: inputStatus)
        }
        if let conversionError { throw conversionError }
        guard status == .haveData || status == .inputRanDry else {
            throw NSError(
                domain: "Record.AudioFileWritePump",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "audio conversion did not produce data"]
            )
        }
        return output
    }

    private func writeSilence(frames: Int64) throws {
        var remaining = frames
        while remaining > 0 {
            let frameCount = AVAudioFrameCount(min(remaining, 4_096))
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: processingFormat,
                frameCapacity: frameCount
            ) else {
                throw NSError(
                    domain: "Record.AudioFileWritePump",
                    code: 4,
                    userInfo: [NSLocalizedDescriptionKey: "silence buffer allocation failed"]
                )
            }
            buffer.frameLength = frameCount
            for audioBuffer in UnsafeMutableAudioBufferListPointer(
                buffer.mutableAudioBufferList
            ) {
                if let data = audioBuffer.mData {
                    memset(data, 0, Int(audioBuffer.mDataByteSize))
                }
            }
            try file?.write(from: buffer)
            remaining -= Int64(frameCount)
        }
    }

    private func report(_ event: Event) {
        var shouldReport = false
        lock.withLock {
            state.droppedForBackpressure += 1
            if !reportedQueuePressure {
                reportedQueuePressure = true
                shouldReport = true
            }
        }
        if shouldReport { onEvent(event) }
    }

    private static func copy(_ source: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard
            let destination = AVAudioPCMBuffer(
                pcmFormat: source.format,
                frameCapacity: source.frameLength
            )
        else { return nil }
        destination.frameLength = source.frameLength

        let sourceBuffers = UnsafeMutableAudioBufferListPointer(
            source.mutableAudioBufferList
        )
        let destinationBuffers = UnsafeMutableAudioBufferListPointer(
            destination.mutableAudioBufferList
        )
        guard sourceBuffers.count == destinationBuffers.count else { return nil }

        for index in sourceBuffers.indices {
            let sourceBuffer = sourceBuffers[index]
            var destinationBuffer = destinationBuffers[index]
            guard let sourceData = sourceBuffer.mData,
                let destinationData = destinationBuffer.mData
            else { continue }
            let byteCount = min(
                Int(sourceBuffer.mDataByteSize),
                Int(destinationBuffer.mDataByteSize)
            )
            memcpy(destinationData, sourceData, byteCount)
            destinationBuffer.mDataByteSize = UInt32(byteCount)
            destinationBuffers[index] = destinationBuffer
        }
        return destination
    }
}

private final class ConverterInput: @unchecked Sendable {
    private let lock = NSLock()
    private let buffer: AVAudioPCMBuffer
    private var supplied = false

    init(buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }

    func next(
        status: UnsafeMutablePointer<AVAudioConverterInputStatus>
    ) -> AVAudioBuffer? {
        lock.withLock {
            guard !supplied else {
                status.pointee = .noDataNow
                return nil
            }
            supplied = true
            status.pointee = .haveData
            return buffer
        }
    }
}
