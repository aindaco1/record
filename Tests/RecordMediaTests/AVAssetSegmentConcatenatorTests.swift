import AVFoundation
import Foundation
import RecordCapture
import RecordCore
import RecordMedia
import XCTest

final class AVAssetSegmentConcatenatorTests: XCTestCase {
    func testConcatenatesIndependentTracksWithPassthroughAndPreservesSegments() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = try await makeSegment(index: 1, in: directory, timestampSeconds: 10)
        let second = try await makeSegment(index: 2, in: directory, timestampSeconds: 20)
        let firstDuration = try await AVURLAsset(url: try XCTUnwrap(first.artifacts[.screen]))
            .load(.duration)
        let finalURLs: [ScreenCaptureSampleKind: URL] = [
            .screen: directory.appendingPathComponent("recording.mov"),
            .systemAudio: directory.appendingPathComponent("system.caf"),
            .microphone: directory.appendingPathComponent("mic.caf"),
        ]

        let result = try await AVAssetSegmentConcatenator().concatenate(
            [first, second],
            to: finalURLs
        )

        XCTAssertEqual(result.files, finalURLs)
        XCTAssertEqual(
            result.startOffsetMilliseconds, [.screen: 0, .systemAudio: 0, .microphone: 0])
        for segment in [first, second] {
            for file in segment.artifacts.files.values {
                XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
            }
        }
        let movie = AVURLAsset(url: try XCTUnwrap(result[.screen]))
        let videoTracks = try await movie.loadTracks(withMediaType: .video)
        let movieAudioTracks = try await movie.loadTracks(withMediaType: .audio)
        let movieDuration = try await movie.load(.duration)
        XCTAssertEqual(videoTracks.count, 1)
        XCTAssertTrue(movieAudioTracks.isEmpty)
        XCTAssertGreaterThan(CMTimeGetSeconds(movieDuration), CMTimeGetSeconds(firstDuration))
        let sourceVideo = AVURLAsset(url: try XCTUnwrap(first.artifacts[.screen]))
        let sourceVideoSubtype = try await mediaSubtype(of: sourceVideo, mediaType: .video)
        let outputVideoSubtype = try await mediaSubtype(of: movie, mediaType: .video)
        XCTAssertEqual(sourceVideoSubtype, outputVideoSubtype)
        for kind in [ScreenCaptureSampleKind.systemAudio, .microphone] {
            let audio = AVURLAsset(url: try XCTUnwrap(result[kind]))
            let audioTracks = try await audio.loadTracks(withMediaType: .audio)
            XCTAssertEqual(audioTracks.count, 1)
            let sourceAudio = AVURLAsset(url: try XCTUnwrap(first.artifacts[kind]))
            let sourceAudioSubtype = try await mediaSubtype(of: sourceAudio, mediaType: .audio)
            let outputAudioSubtype = try await mediaSubtype(of: audio, mediaType: .audio)
            XCTAssertEqual(sourceAudioSubtype, outputAudioSubtype)
        }
    }

    func testSingleSegmentCopiesBytesWithoutReencoding() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let segment = try await makeSegment(index: 1, in: directory, timestampSeconds: 10)
        let finalURLs: [ScreenCaptureSampleKind: URL] = [
            .screen: directory.appendingPathComponent("recording.mov"),
            .systemAudio: directory.appendingPathComponent("system.caf"),
            .microphone: directory.appendingPathComponent("mic.caf"),
        ]

        let result = try await AVAssetSegmentConcatenator().concatenate(
            [segment],
            to: finalURLs
        )

        for kind in ScreenCaptureSampleKind.allCases {
            XCTAssertEqual(
                try Data(contentsOf: try XCTUnwrap(segment.artifacts[kind])),
                try Data(contentsOf: try XCTUnwrap(result[kind]))
            )
        }
    }

    func testRejectsGapsOrIncompatibleTrackSets() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let segment = try await makeSegment(index: 2, in: directory, timestampSeconds: 10)

        await XCTAssertThrowsErrorAsync(
            try await AVAssetSegmentConcatenator().concatenate(
                [segment],
                to: [.screen: directory.appendingPathComponent("recording.mov")]
            )
        ) { error in
            XCTAssertEqual(
                error as? AVAssetSegmentConcatenator.ConcatenationError,
                .invalidSegmentOrder
            )
        }
    }

    private func makeSegment(
        index: Int,
        in directory: URL,
        timestampSeconds: Int64
    ) async throws -> CaptureSegmentArtifactSet {
        let stem = String(format: "segment-%04d", index)
        let finalURLs: [ScreenCaptureSampleKind: URL] = [
            .screen: directory.appendingPathComponent("\(stem).mov"),
            .systemAudio: directory.appendingPathComponent("\(stem)-system.caf"),
            .microphone: directory.appendingPathComponent("\(stem)-mic.caf"),
        ]
        let configuration = CaptureConfiguration(
            source: .display(id: 1),
            outputSize: .init(width: 320, height: 180)
        )
        let writer = try AVAssetSegmentWriter(
            plan: SegmentWriterPlan(configuration: configuration),
            output: try SegmentOutputSet(finalURLs: finalURLs)
        )
        for frame in 0..<30 {
            try await processWhenReady(
                makeTestSample(
                    value: timestampSeconds * 60 + Int64(frame),
                    width: 320,
                    height: 180
                ),
                with: writer
            )
        }
        for kind in [ScreenCaptureSampleKind.systemAudio, .microphone] {
            try await processWhenReady(
                makeTestAudioSample(
                    value: timestampSeconds * 48_000,
                    frameCount: 24_000,
                    kind: kind
                ),
                with: writer
            )
        }
        guard case .finalized(let artifacts) = try await writer.finish() else {
            throw TestError.emptySegment
        }
        return CaptureSegmentArtifactSet(index: index, artifacts: artifacts)
    }

    private func processWhenReady(
        _ sample: ScreenCaptureSample,
        with writer: AVAssetSegmentWriter
    ) async throws {
        while try writer.process(sample) == .dropped(.writerBackpressure) {
            try await Task.sleep(for: .milliseconds(1))
        }
    }

    private func mediaSubtype(
        of asset: AVAsset,
        mediaType: AVMediaType
    ) async throws -> FourCharCode {
        let tracks = try await asset.loadTracks(withMediaType: mediaType)
        let track = try XCTUnwrap(tracks.first)
        let descriptions = try await track.load(.formatDescriptions)
        let description = try XCTUnwrap(descriptions.first)
        return CMFormatDescriptionGetMediaSubType(description)
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "record-segment-concat-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        return directory
    }

    private enum TestError: Error {
        case emptySegment
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
