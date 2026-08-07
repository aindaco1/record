import AVFoundation
@testable import Record
import XCTest

final class AudioFileWritePumpTests: XCTestCase {
    func testConvertsRouteFormatAndPadsTimelineOffCaptureCallback() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let target = try XCTUnwrap(
            AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 48_000,
                channels: 1,
                interleaved: false
            )
        )
        let source = try XCTUnwrap(
            AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 44_100,
                channels: 2,
                interleaved: false
            )
        )
        let file = try AVAudioFile(
            forWriting: fixture.file,
            settings: target.settings,
            commonFormat: target.commonFormat,
            interleaved: target.isInterleaved
        )
        let pump = AudioFileWritePump(file: file)
        let buffer = try XCTUnwrap(
            AVAudioPCMBuffer(pcmFormat: source, frameCapacity: 4_410)
        )
        buffer.frameLength = 4_410
        for channel in 0..<Int(source.channelCount) {
            for frame in 0..<Int(buffer.frameLength) {
                buffer.floatChannelData?[channel][frame] = 0.1
            }
        }

        pump.enqueueOwned(buffer)
        pump.enqueueSilence(durationMilliseconds: 100)
        pump.finish()

        let snapshot = pump.snapshot()
        XCTAssertEqual(snapshot.receivedBuffers, 1)
        XCTAssertEqual(snapshot.writtenBuffers, 1)
        XCTAssertEqual(snapshot.paddedFrames, 4_800)
        XCTAssertFalse(snapshot.writeFailed)
        let recorded = try AVAudioFile(forReading: fixture.file)
        // A streaming sample-rate converter retains a small fixed priming
        // tail until the next callback. Timeline padding itself is exact and
        // the route-format conversion remains within that bounded latency.
        XCTAssertEqual(recorded.length, 9_600, accuracy: 512)
    }

    func testQueuePressureIsBoundedAndReportedOnce() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let format = try XCTUnwrap(
            AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 48_000,
                channels: 1,
                interleaved: false
            )
        )
        let file = try AVAudioFile(
            forWriting: fixture.file,
            settings: format.settings,
            commonFormat: format.commonFormat,
            interleaved: format.isInterleaved
        )
        let worker = DispatchQueue(label: "AudioFileWritePumpTests.suspended")
        worker.suspend()
        let events = EventCollector()
        let pump = AudioFileWritePump(file: file, capacity: 1, worker: worker) {
            events.append($0)
        }
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16))
        buffer.frameLength = 16

        pump.enqueueOwned(buffer)
        pump.enqueueOwned(buffer)
        pump.enqueueOwned(buffer)
        XCTAssertEqual(pump.snapshot().highWatermark, 1)
        XCTAssertEqual(pump.snapshot().droppedForBackpressure, 2)
        XCTAssertEqual(events.values, [.queuePressure])

        worker.resume()
        pump.finish()
    }

    private func makeFixture() throws -> (directory: URL, file: URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "AudioFileWritePumpTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (directory, directory.appendingPathComponent("audio.caf"))
    }
}

private final class EventCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [AudioFileWritePump.Event] = []

    var values: [AudioFileWritePump.Event] { lock.withLock { events } }
    func append(_ event: AudioFileWritePump.Event) { lock.withLock { events.append(event) } }
}
