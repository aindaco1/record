import Foundation
import RecordCapture
import RecordCore
import RecordMedia
import XCTest

final class AVAssetSegmentWriterTests: XCTestCase {
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
        let output = try SegmentOutput(
            finalURL: directory.appendingPathComponent("segment-0001.mov")
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
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.finalURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.partialURL.path))
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
        let output = try SegmentOutput(
            finalURL: directory.appendingPathComponent("segment-0001.mov")
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
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.finalURL.path))
    }
}
