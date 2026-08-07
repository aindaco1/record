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
        let health = HealthRecorder()
        let sink = BoundedScreenCaptureSink(
            configuration: configuration,
            processor: processor,
            onHealth: { health.record(kind: $0, code: $1, severity: $2) }
        )

        sink.consume(try makeTestSample(value: 1))
        XCTAssertEqual(processor.started.wait(timeout: .now() + 2), .success)
        sink.consume(try makeTestSample(value: 2))
        sink.consume(try makeTestSample(value: 3))
        sink.consume(try makeTestSample(value: 4))

        let congested = sink.snapshot()[.screen]
        XCTAssertEqual(congested.pending, 2)
        XCTAssertEqual(congested.highWatermark, 2)
        XCTAssertEqual(congested.droppedForBackpressure, 1)
        XCTAssertEqual(
            health.values,
            [.init(kind: .screen, code: .queuePressure, severity: .degraded)]
        )

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
        let health = HealthRecorder()
        let sink = BoundedScreenCaptureSink(
            configuration: try MediaIngressConfiguration(),
            processor: processor,
            onFailure: { reported.record($0) },
            onHealth: { health.record(kind: $0, code: $1, severity: $2) }
        )

        sink.consume(try makeTestSample(value: 1))
        await XCTAssertThrowsErrorAsync(try await sink.finish()) { error in
            XCTAssertEqual(error as? MediaIngressError, .processingFailed(expected))
        }
        sink.consume(try makeTestSample(value: 2))

        XCTAssertEqual(reported.failure(), expected)
        let snapshot = sink.snapshot()[.screen]
        XCTAssertEqual(snapshot.discardedAfterFailure, 1)
        XCTAssertEqual(snapshot.rejectedAfterFinish, 1)
        XCTAssertEqual(
            health.values,
            [.init(kind: .screen, code: .writeFailed, severity: .failed)]
        )
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
        sink.consume(try makeTestSample(value: 1))
        XCTAssertEqual(processor.started.wait(timeout: .now() + 2), .success)

        let firstFinish = Task { try await sink.finish() }
        let secondFinish = Task { try await sink.finish() }
        processor.release.signal()

        try await firstFinish.value
        try await secondFinish.value
        try await sink.finish()
        XCTAssertEqual(processor.values(), [1])
    }

    func testProcessorDropsAreDistinctFromIngressBackpressure() async throws {
        let sink = BoundedScreenCaptureSink(
            configuration: try MediaIngressConfiguration(),
            processor: DroppingProcessor()
        )

        sink.consume(try makeTestSample(value: 1))
        try await sink.finish()

        let snapshot = sink.snapshot()[.screen]
        XCTAssertEqual(snapshot.processed, 0)
        XCTAssertEqual(snapshot.droppedByProcessor, 1)
        XCTAssertEqual(snapshot.droppedForBackpressure, 0)
    }

}

private final class HealthRecorder: @unchecked Sendable {
    struct Entry: Equatable {
        let kind: ScreenCaptureSampleKind
        let code: CaptureHealthEvent.Code
        let severity: CaptureHealthEvent.Severity
    }

    private let lock = NSLock()
    private var entries: [Entry] = []

    var values: [Entry] { lock.withLock { entries } }

    func record(
        kind: ScreenCaptureSampleKind,
        code: CaptureHealthEvent.Code,
        severity: CaptureHealthEvent.Severity
    ) {
        lock.withLock { entries.append(.init(kind: kind, code: code, severity: severity)) }
    }
}

private final class BlockingProcessor: MediaSampleProcessing, @unchecked Sendable {
    let started = DispatchSemaphore(value: 0)
    let release = DispatchSemaphore(value: 0)

    private let lock = NSLock()
    private var processedValues: [Int64] = []
    private var isFirst = true

    func process(_ sample: ScreenCaptureSample) -> MediaSampleProcessingResult {
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
        return .consumed
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

    func process(_ sample: ScreenCaptureSample) throws -> MediaSampleProcessingResult {
        throw MediaSampleProcessingFailure(failure)
    }
}

private final class DroppingProcessor: MediaSampleProcessing, @unchecked Sendable {
    func process(_ sample: ScreenCaptureSample) -> MediaSampleProcessingResult {
        .dropped(.writerBackpressure)
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
