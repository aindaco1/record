import AVFoundation
import CoreVideo
import Foundation
import RecordCapture
import RecordCore
import RecordMedia
import XCTest

final class AVAssetSegmentWriterTests: XCTestCase {
    func testFirstSamplesCanReachIndependentWritersOutOfTimestampOrder() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "record-independent-timeline-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }

        let configuration = CaptureConfiguration(
            source: .display(id: 1),
            outputSize: .init(width: 64, height: 64)
        )
        let output = try SegmentOutputSet(
            screenURL: directory.appendingPathComponent("recording.mov"),
            includesSystemAudio: true,
            includesMicrophone: true
        )
        let writer = try AVAssetSegmentWriter(
            plan: SegmentWriterPlan(configuration: configuration),
            output: output
        )

        // These mimic independent callback queues: arrival order is the
        // reverse of presentation-time order.
        try await processWhenReady(
            makeTestAudioSample(value: 489_600, kind: .systemAudio),
            with: writer
        )
        try await processWhenReady(
            makeTestAudioSample(value: 484_800, kind: .microphone),
            with: writer
        )
        try await processWhenReady(
            makeTestSample(value: 600, width: 64, height: 64),
            with: writer
        )

        let result = try await writer.finish()
        guard case .finalized(let artifacts) = result else {
            return XCTFail("expected finalized media")
        }
        XCTAssertEqual(
            artifacts.startOffsetMilliseconds,
            [.screen: 0, .microphone: 100, .systemAudio: 200]
        )
        for kind in ScreenCaptureSampleKind.allCases {
            let file = try XCTUnwrap(artifacts[kind])
            XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        }
        let videoTracks = try await AVURLAsset(url: try XCTUnwrap(artifacts[.screen]))
            .loadTracks(withMediaType: .video)
        XCTAssertEqual(videoTracks.count, 1)
        for kind in [ScreenCaptureSampleKind.systemAudio, .microphone] {
            let audioTracks = try await AVURLAsset(url: try XCTUnwrap(artifacts[kind]))
                .loadTracks(withMediaType: .audio)
            XCTAssertEqual(audioTracks.count, 1)
        }
    }

    func testEmptySegmentFinishesWithoutPublishingAFile() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "record-empty-segment-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }

        let configuration = CaptureConfiguration(
            source: .display(id: 1),
            outputSize: .init(width: 1_920, height: 1_080)
        )
        let output = try SegmentOutputSet(
            screenURL: directory.appendingPathComponent("segment-0001.mov"),
            includesSystemAudio: true,
            includesMicrophone: true
        )
        let writer = try AVAssetSegmentWriter(
            plan: SegmentWriterPlan(configuration: configuration),
            output: output
        )

        let firstResult = try await writer.finish()
        let secondResult = try await writer.finish()
        XCTAssertEqual(firstResult, .empty)
        XCTAssertEqual(secondResult, .empty)
        XCTAssertEqual(writer.state, .completed)
        for destination in output.outputs.values {
            XCTAssertFalse(FileManager.default.fileExists(atPath: destination.finalURL.path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: destination.partialURL.path))
        }
    }

    func testDisabledAudioTrackDropsWithoutStartingOrPublishing() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "record-disabled-track-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let configuration = CaptureConfiguration(
            source: .display(id: 1),
            outputSize: .init(width: 1_920, height: 1_080),
            audio: .init(includeSystemAudio: false, includeMicrophone: false)
        )
        let output = try SegmentOutputSet(
            screenURL: directory.appendingPathComponent("segment-0001.mov"),
            includesSystemAudio: false,
            includesMicrophone: false
        )
        let writer = try AVAssetSegmentWriter(
            plan: SegmentWriterPlan(configuration: configuration),
            output: output
        )

        let disposition = try writer.process(
            makeTestSample(value: 1, kind: .systemAudio)
        )

        XCTAssertEqual(disposition, .dropped(.trackDisabled))
        XCTAssertEqual(writer.state, .configured)
        let result = try await writer.finish()
        XCTAssertEqual(result, .empty)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: try XCTUnwrap(output[.screen]).finalURL.path
            )
        )
    }

    /// Opt-in regression harness for a real ScreenCaptureKit recording:
    /// RECORD_MEDIA_FIXTURE=/path/to/multitrack.mov swift test --filter
    /// AVAssetSegmentWriterTests/testExternalMultitrackFixtureSplitsIntoIndependentFiles
    func testExternalMultitrackFixtureSplitsIntoIndependentFiles() async throws {
        guard let fixturePath = ProcessInfo.processInfo.environment["RECORD_MEDIA_FIXTURE"] else {
            throw XCTSkip("set RECORD_MEDIA_FIXTURE to a multitrack screen recording")
        }
        let fixtureURL = URL(fileURLWithPath: fixturePath)
        let asset = AVURLAsset(url: fixtureURL)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let videoTrack = try XCTUnwrap(videoTracks.first)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard audioTracks.count == 2 else {
            return XCTFail("fixture must contain system and microphone audio tracks")
        }

        let size = try await videoTrack.load(.naturalSize)
        let width = max(16, Int(abs(size.width)).roundedDownToEven)
        let height = max(16, Int(abs(size.height)).roundedDownToEven)
        let configuration = CaptureConfiguration(
            source: .display(id: 1),
            outputSize: .init(width: width, height: height)
        )
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "record-external-segment-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }

        let outputs = try SegmentOutputSet(
            screenURL: directory.appendingPathComponent("recording.mov"),
            includesSystemAudio: true,
            includesMicrophone: true
        )
        let writer = try AVAssetSegmentWriter(
            plan: SegmentWriterPlan(configuration: configuration),
            output: outputs
        )
        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = CMTimeRange(
            start: .zero, duration: CMTime(seconds: 2, preferredTimescale: 600))

        let videoOutput = AVAssetReaderTrackOutput(
            track: videoTrack,
            outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String:
                    kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
            ]
        )
        let systemOutput = AVAssetReaderTrackOutput(
            track: audioTracks[0],
            outputSettings: Self.linearPCMAudioSettings()
        )
        let microphoneOutput = AVAssetReaderTrackOutput(
            track: audioTracks[1],
            outputSettings: Self.linearPCMAudioSettings()
        )
        let readerOutputs: [(ScreenCaptureSampleKind, AVAssetReaderOutput)] = [
            (.screen, videoOutput),
            (.systemAudio, systemOutput),
            (.microphone, microphoneOutput),
        ]
        for (_, output) in readerOutputs {
            XCTAssertTrue(reader.canAdd(output))
            reader.add(output)
        }
        XCTAssertTrue(reader.startReading())

        var pending = readerOutputs.map { kind, output in
            (kind, output, output.copyNextSampleBuffer())
        }
        while let nextIndex = pending.indices.min(by: { left, right in
            let lhs =
                pending[left].2.map(CMSampleBufferGetPresentationTimeStamp) ?? .positiveInfinity
            let rhs =
                pending[right].2.map(CMSampleBufferGetPresentationTimeStamp) ?? .positiveInfinity
            return CMTimeCompare(lhs, rhs) < 0
        }), let sampleBuffer = pending[nextIndex].2 {
            let kind = pending[nextIndex].0
            let sample = ScreenCaptureSample(
                kind: kind,
                timestamp: try ScreenCaptureTimestamp(
                    validating: CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                ),
                buffer: sampleBuffer
            )
            while try writer.process(sample) == .dropped(.writerBackpressure) {
                try await Task.sleep(for: .milliseconds(1))
            }
            pending[nextIndex].2 = pending[nextIndex].1.copyNextSampleBuffer()
        }
        XCTAssertEqual(reader.status, .completed)

        let result = try await writer.finish()
        guard case .finalized(let artifacts) = result else {
            return XCTFail("expected finalized media")
        }
        let screenURL = try XCTUnwrap(artifacts[.screen])
        let systemURL = try XCTUnwrap(artifacts[.systemAudio])
        let microphoneURL = try XCTUnwrap(artifacts[.microphone])
        let outputMovie = AVURLAsset(url: screenURL)
        let outputVideoTracks = try await outputMovie.loadTracks(withMediaType: .video)
        let outputMovieAudioTracks = try await outputMovie.loadTracks(withMediaType: .audio)
        let outputSystemTracks = try await AVURLAsset(url: systemURL).loadTracks(
            withMediaType: .audio
        )
        let outputMicrophoneTracks = try await AVURLAsset(url: microphoneURL).loadTracks(
            withMediaType: .audio
        )
        XCTAssertEqual(outputVideoTracks.count, 1)
        XCTAssertEqual(outputMovieAudioTracks.count, 0)
        XCTAssertEqual(outputSystemTracks.count, 1)
        XCTAssertEqual(outputMicrophoneTracks.count, 1)
    }

    private static func linearPCMAudioSettings() -> [String: Any] {
        [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
        ]
    }

    private func processWhenReady(
        _ sample: ScreenCaptureSample,
        with writer: AVAssetSegmentWriter
    ) async throws {
        while try writer.process(sample) == .dropped(.writerBackpressure) {
            try await Task.sleep(for: .milliseconds(1))
        }
    }
}

private extension Int {
    var roundedDownToEven: Int { self - self % 2 }
}
