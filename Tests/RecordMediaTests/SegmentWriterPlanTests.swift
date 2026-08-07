import AVFoundation
import RecordCore
import RecordMedia
import VideoToolbox
import XCTest

final class SegmentWriterPlanTests: XCTestCase {
    func test4K60HEVCSettingsRequireRealTimeHardwareEncoding() throws {
        let plan = try SegmentWriterPlan(
            configuration: CaptureConfiguration(
                source: .display(id: 1),
                outputSize: .init(width: 4_096, height: 2_160),
                frameRate: .fps60,
                audio: .init(includeSystemAudio: true, includeMicrophone: true)
            )
        )

        XCTAssertEqual(plan.bitRate, SegmentWriterPlan.maximumBitRate)
        let settings = plan.makeVideoSettings()
        XCTAssertEqual(settings[AVVideoCodecKey] as? AVVideoCodecType, .hevc)
        XCTAssertEqual(settings[AVVideoWidthKey] as? Int, 4_096)
        XCTAssertEqual(settings[AVVideoHeightKey] as? Int, 2_160)

        let specification = settings[AVVideoEncoderSpecificationKey] as? [String: Any]
        XCTAssertEqual(
            specification?[
                kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder as String
            ] as? Bool,
            true
        )
        let compression = settings[AVVideoCompressionPropertiesKey] as? [String: Any]
        XCTAssertEqual(compression?[AVVideoExpectedSourceFrameRateKey] as? Int, 60)
        XCTAssertEqual(compression?[AVVideoAllowFrameReorderingKey] as? Bool, false)
        XCTAssertEqual(
            compression?[kVTCompressionPropertyKey_RealTime as String] as? Bool,
            true
        )
        XCTAssertEqual(
            compression?[kVTCompressionPropertyKey_AverageBitRate as String] as? Int,
            SegmentWriterPlan.maximumBitRate
        )
        XCTAssertEqual(
            compression?[kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration as String]
                as? Double,
            2.0
        )
        XCTAssertEqual(
            compression?[AVVideoProfileLevelKey] as? String,
            kVTProfileLevel_HEVC_Main_AutoLevel as String
        )
        let writer = try validationWriter()
        XCTAssertTrue(writer.canApply(outputSettings: settings, forMediaType: .video))
    }

    func testRejectsUnmeasuredBitRates() {
        let configuration = CaptureConfiguration(
            source: .display(id: 1),
            outputSize: .init(width: 1_920, height: 1_080)
        )

        XCTAssertThrowsError(
            try SegmentWriterPlan(configuration: configuration, bitRate: 50_000_001)
        ) { error in
            XCTAssertEqual(error as? SegmentWriterError, .invalidBitRate(50_000_001))
        }
    }

    func testAudioTracksStaySeparatelyConfigured() throws {
        let plan = try SegmentWriterPlan(
            configuration: CaptureConfiguration(
                source: .window(id: 1),
                outputSize: .init(width: 1_920, height: 1_080),
                audio: .init(includeSystemAudio: true, includeMicrophone: false)
            )
        )

        XCTAssertTrue(plan.includesSystemAudio)
        XCTAssertFalse(plan.includesMicrophone)
        let writer = try validationWriter()
        XCTAssertTrue(
            writer.canApply(outputSettings: plan.makeAudioSettings(), forMediaType: .audio)
        )
        let cafWriter = try validationAudioWriter()
        XCTAssertTrue(
            cafWriter.canApply(outputSettings: plan.makeAudioSettings(), forMediaType: .audio)
        )
    }

    private func validationWriter() throws -> AVAssetWriter {
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "record-writer-settings-\(UUID().uuidString).mov"
        )
        return try AVAssetWriter(outputURL: outputURL, fileType: .mov)
    }

    private func validationAudioWriter() throws -> AVAssetWriter {
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "record-writer-settings-\(UUID().uuidString).caf"
        )
        return try AVAssetWriter(outputURL: outputURL, fileType: .caf)
    }
}
