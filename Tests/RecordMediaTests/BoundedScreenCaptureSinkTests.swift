import CoreMedia
import CoreVideo
import Dispatch
import RecordCapture
import RecordCore
import RecordMedia
import XCTest

final class BoundedScreenCaptureSinkTests: XCTestCase {
    func testSlowProcessorEvictsOldestAndFinishesDeterministically() async throws {
        let processor = BlockingProcessor()
        let configuration = try MediaIngressConfiguration(
            screenCapacity: 2,
            systemAudioCapacity: 2,
            microphoneCapacity: 2
        )
        let sink = BoundedScreenCaptureSink(
            configuration: configuration,
            processor: processor
        )

        sink.consume(try sample(value: 1))
        XCTAssertEqual(processor.started.wait(timeout: .now() + 2), .success)
        sink.consume(try sample(value: 2))
        sink.consume(try sample(value: 3))
        sink.consume(try sample(value: 4))

        let congested = sink.snapshot()[.screen]
        XCTAssertEqual(congested.pending, 2)
        XCTAssertEqual(congested.highWatermark, 2)
        XCTAssertEqual(congested.droppedForBackpressure, 1)

        processor.release.signal()
        try await sink.finish()

        XCTAssertEqual(processor.values(), [1, 3, 4])
        let finished = sink.snapshot()[.screen]
        XCTAssertEqual(finished.received, 4)
        XCTAssertEqual(finished.processed, 3)
        XCTAssertEqual(finished.pending, 0)
    }

    func testProcessorFailureIsSanitizedPropagatedAndSealsIngress() async throws {
        let expected = CaptureFailure(code: .encoderFailed, summary: "hardware encoder failed")
        let processor = FailingProcessor(failure: expected)
        let reported = FailureRecorder()
        let sink = BoundedScreenCaptureSink(
            configuration: try MediaIngressConfiguration(),
            processor: processor,
            onFailure: { reported.record($0) }
        )

        sink.consume(try sample(value: 1))
        await XCTAssertThrowsErrorAsync(try await sink.finish()) { error in
            XCTAssertEqual(error as? MediaIngressError, .processingFailed(expected))
        }
        sink.consume(try sample(value: 2))

        XCTAssertEqual(reported.failure(), expected)
        let snapshot = sink.snapshot()[.screen]
        XCTAssertEqual(snapshot.discardedAfterFailure, 1)
        XCTAssertEqual(snapshot.rejectedAfterFinish, 1)
    }

    func testRejectsCapacitiesThatCouldHideUnboundedConfiguration() {
        XCTAssertThrowsError(
            try MediaIngressConfiguration(screenCapacity: 9)
        ) { error in
            XCTAssertEqual(
                error as? MediaIngressError,
                .invalidCapacity(kind: .screen, value: 9)
            )
        }
        XCTAssertThrowsError(
            try MediaIngressConfiguration(microphoneCapacity: 129)
        ) { error in
            XCTAssertEqual(
                error as? MediaIngressError,
                .invalidCapacity(kind: .microphone, value: 129)
            )
        }
    }

    func testConcurrentFinishCallsWaitForTheSameDrain() async throws {
        let processor = BlockingProcessor()
        let sink = BoundedScreenCaptureSink(
            configuration: try MediaIngressConfiguration(),
            processor: processor
        )
        sink.consume(try sample(value: 1))
        XCTAssertEqual(processor.started.wait(timeout: .now() + 2), .success)

        let firstFinish = Task { try await sink.finish() }
        let secondFinish = Task { try await sink.finish() }
        processor.release.signal()

        try await firstFinish.value
        try await secondFinish.value
        try await sink.finish()
        XCTAssertEqual(processor.values(), [1])
    }

    private func sample(value: Int64) throws -> ScreenCaptureSample {
        let presentationTime = CMTime(value: value, timescale: 60)
        var pixelBuffer: CVPixelBuffer?
        let pixelStatus = CVPixelBufferCreate(
            kCFAllocatorDefault,
            2,
            2,
            kCVPixelFormatType_32BGRA,
            nil,
            &pixelBuffer
        )
        guard pixelStatus == kCVReturnSuccess, let pixelBuffer else {
            throw TestSampleError.creationFailed(pixelStatus)
        }

        var formatDescription: CMVideoFormatDescription?
        let formatStatus = CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDescription
        )
        guard formatStatus == noErr, let formatDescription else {
            throw TestSampleError.creationFailed(formatStatus)
        }

        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 60),
            presentationTimeStamp: presentationTime,
            decodeTimeStamp: .invalid
        )
        var sampleBuffer: CMSampleBuffer?
        let sampleStatus = CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: formatDescription,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        )
        guard sampleStatus == noErr, let sampleBuffer else {
            throw TestSampleError.creationFailed(sampleStatus)
        }
        return ScreenCaptureSample(
            kind: .screen,
            timestamp: try ScreenCaptureTimestamp(validating: presentationTime),
            buffer: sampleBuffer
        )
    }
}

private enum TestSampleError: Error {
    case creationFailed(OSStatus)
}

private final class BlockingProcessor: MediaSampleProcessing, @unchecked Sendable {
    let started = DispatchSemaphore(value: 0)
    let release = DispatchSemaphore(value: 0)

    private let lock = NSLock()
    private var processedValues: [Int64] = []
    private var isFirst = true

    func process(_ sample: ScreenCaptureSample) {
        lock.lock()
        let shouldBlock = isFirst
        isFirst = false
        lock.unlock()
        if shouldBlock {
            started.signal()
            release.wait()
        }
        lock.lock()
        processedValues.append(sample.timestamp.time.value)
        lock.unlock()
    }

    func values() -> [Int64] {
        lock.lock()
        let values = processedValues
        lock.unlock()
        return values
    }
}

private final class FailingProcessor: MediaSampleProcessing, @unchecked Sendable {
    private let failure: CaptureFailure

    init(failure: CaptureFailure) {
        self.failure = failure
    }

    func process(_ sample: ScreenCaptureSample) throws {
        throw MediaSampleProcessingFailure(failure)
    }
}

private final class FailureRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedFailure: CaptureFailure?

    func record(_ failure: CaptureFailure) {
        lock.lock()
        recordedFailure = failure
        lock.unlock()
    }

    func failure() -> CaptureFailure? {
        lock.lock()
        let failure = recordedFailure
        lock.unlock()
        return failure
    }
}

private func XCTAssertThrowsErrorAsync(
    _ expression: @autoclosure () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line,
    _ errorHandler: (Error) -> Void = { _ in }
) async {
    do {
        try await expression()
        XCTFail("Expected expression to throw", file: file, line: line)
    } catch {
        errorHandler(error)
    }
}
