import RecordCapture
import XCTest

final class ScreenCaptureSessionTests: XCTestCase {
    func testStartAndStopAreIdempotent() async throws {
        let driver = CountingDriver()
        let session = ScreenCaptureSession(driver: driver)

        try await session.start()
        try await session.start()
        try await session.stop()
        try await session.stop()

        let counts = await driver.counts()
        let state = await session.state
        XCTAssertEqual(counts.starts, 1)
        XCTAssertEqual(counts.stops, 1)
        XCTAssertEqual(state, .stopped)
    }

    func testStopDuringStartCompletesAfterStartWithoutLeakingStream() async throws {
        let driver = SuspendedStartDriver()
        let session = ScreenCaptureSession(driver: driver)
        let start = Task { try await session.start() }

        await driver.waitUntilStartBegins()
        let stop = Task { try await session.stop() }
        await driver.finishStart()
        try await start.value
        try await stop.value

        let counts = await driver.counts()
        let state = await session.state
        XCTAssertEqual(counts.starts, 1)
        XCTAssertEqual(counts.stops, 1)
        XCTAssertEqual(state, .stopped)
    }

    func testStopBeforeStartDoesNotCallScreenCaptureKitStop() async throws {
        let driver = CountingDriver()
        let session = ScreenCaptureSession(driver: driver)

        try await session.stop()

        let counts = await driver.counts()
        let state = await session.state
        XCTAssertEqual(counts.starts, 0)
        XCTAssertEqual(counts.stops, 0)
        XCTAssertEqual(counts.cancellations, 1)
        XCTAssertEqual(state, .stopped)
    }

    func testConcurrentStopsWhileCancellingPreparedStreamBothComplete() async throws {
        let driver = SuspendedCancelDriver()
        let session = ScreenCaptureSession(driver: driver)
        let firstStop = Task { try await session.stop() }

        await driver.waitUntilCancelBegins()
        let secondStop = Task { try await session.stop() }
        await driver.finishCancel()
        try await firstStop.value
        try await secondStop.value

        let cancellationCount = await driver.cancellationCount()
        let state = await session.state
        XCTAssertEqual(cancellationCount, 1)
        XCTAssertEqual(state, .stopped)
    }

    func testFailedNativeStopDetachesOutputsAndReleasesDriver() async throws {
        let driver = FailingStopDriver()
        let session = ScreenCaptureSession(driver: driver)

        try await session.start()
        await XCTAssertThrowsErrorAsync(try await session.stop())

        let counts = await driver.counts()
        let state = await session.state
        XCTAssertEqual(counts.stops, 1)
        XCTAssertEqual(counts.cancellations, 1)
        XCTAssertEqual(state, .failed)

        try await session.stop()
        let stateAfterCleanup = await session.state
        XCTAssertEqual(stateAfterCleanup, .stopped)
    }
}

private func XCTAssertThrowsErrorAsync(
    _ expression: @autoclosure () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("Expected expression to throw", file: file, line: line)
    } catch {}
}

private actor CountingDriver: ScreenCaptureStreamDriving {
    private var startCount = 0
    private var stopCount = 0
    private var cancellationCount = 0

    func startCapture() {
        startCount += 1
    }

    func stopCapture() {
        stopCount += 1
    }

    func cancelCapture() {
        cancellationCount += 1
    }

    func counts() -> (starts: Int, stops: Int, cancellations: Int) {
        (startCount, stopCount, cancellationCount)
    }
}

private actor SuspendedStartDriver: ScreenCaptureStreamDriving {
    private var startCount = 0
    private var stopCount = 0
    private var cancellationCount = 0
    private var startBegan = false
    private var startContinuation: CheckedContinuation<Void, Never>?

    func startCapture() async {
        startCount += 1
        startBegan = true
        await withCheckedContinuation { continuation in
            startContinuation = continuation
        }
    }

    func stopCapture() {
        stopCount += 1
    }

    func cancelCapture() {
        cancellationCount += 1
    }

    func waitUntilStartBegins() async {
        while !startBegan {
            await Task.yield()
        }
    }

    func finishStart() {
        startContinuation?.resume()
        startContinuation = nil
    }

    func counts() -> (starts: Int, stops: Int, cancellations: Int) {
        (startCount, stopCount, cancellationCount)
    }
}

private actor SuspendedCancelDriver: ScreenCaptureStreamDriving {
    private var cancelCount = 0
    private var cancelBegan = false
    private var cancelContinuation: CheckedContinuation<Void, Never>?

    func startCapture() {}

    func stopCapture() {}

    func cancelCapture() async {
        cancelCount += 1
        cancelBegan = true
        await withCheckedContinuation { continuation in
            cancelContinuation = continuation
        }
    }

    func waitUntilCancelBegins() async {
        while !cancelBegan {
            await Task.yield()
        }
    }

    func finishCancel() {
        cancelContinuation?.resume()
        cancelContinuation = nil
    }

    func cancellationCount() -> Int {
        cancelCount
    }
}

private actor FailingStopDriver: ScreenCaptureStreamDriving {
    private var stopCount = 0
    private var cancellationCount = 0

    func startCapture() {}

    func stopCapture() throws {
        stopCount += 1
        throw NSError(domain: "test", code: 1)
    }

    func cancelCapture() {
        cancellationCount += 1
    }

    func counts() -> (stops: Int, cancellations: Int) {
        (stopCount, cancellationCount)
    }
}
