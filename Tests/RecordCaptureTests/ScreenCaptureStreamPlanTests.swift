import CoreGraphics
import CoreMedia
import CoreVideo
import RecordCapture
import RecordCore
import XCTest

final class ScreenCaptureStreamPlanTests: XCTestCase {
    func testMaps4K60CaptureToBoundedEncoderFriendlyConfiguration() throws {
        let plan = try ScreenCaptureStreamPlan(
            configuration: CaptureConfiguration(
                source: .display(id: 7),
                outputSize: .init(width: 4_096, height: 2_160),
                frameRate: .fps60,
                showCursor: true,
                audio: .init(includeSystemAudio: true, includeMicrophone: true)
            )
        )

        XCTAssertEqual(plan.queueDepth, 5)
        XCTAssertEqual(plan.pixelFormat, .videoRange420)
        let configuration = plan.makeStreamConfiguration()
        XCTAssertEqual(configuration.width, 4_096)
        XCTAssertEqual(configuration.height, 2_160)
        XCTAssertEqual(configuration.minimumFrameInterval, CMTime(value: 1, timescale: 60))
        XCTAssertEqual(configuration.queueDepth, 5)
        XCTAssertEqual(
            configuration.pixelFormat,
            kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        )
        XCTAssertEqual(
            configuration.colorMatrix,
            CGDisplayStream.yCbCrMatrix_ITU_R_709_2
        )
        XCTAssertEqual(configuration.colorSpaceName, CGColorSpace.itur_709)
        XCTAssertTrue(configuration.capturesAudio)
        XCTAssertTrue(configuration.captureMicrophone)
        XCTAssertTrue(configuration.excludesCurrentProcessAudio)
        XCTAssertEqual(configuration.sampleRate, 48_000)
        XCTAssertEqual(configuration.channelCount, 2)
    }

    func testClickHighlightSelectsRequiredBGRAFormat() throws {
        let plan = try ScreenCaptureStreamPlan(
            configuration: CaptureConfiguration(
                source: .window(id: 42),
                outputSize: .init(width: 1_920, height: 1_080),
                highlightClicks: true
            )
        )

        XCTAssertEqual(plan.pixelFormat, .bgra)
        let configuration = plan.makeStreamConfiguration()
        XCTAssertEqual(configuration.pixelFormat, kCVPixelFormatType_32BGRA)
        XCTAssertEqual(configuration.colorSpaceName, CGColorSpace.sRGB)
        XCTAssertTrue(configuration.showMouseClicks)
    }

    func testRegionMapsToDisplayLocalSourceRectangle() throws {
        let rect = CaptureRect(x: 100, y: 50, width: 800, height: 600)
        let plan = try ScreenCaptureStreamPlan(
            configuration: CaptureConfiguration(
                source: .region(displayID: 1, rect: rect),
                outputSize: .init(width: 1_600, height: 1_200)
            )
        )

        XCTAssertEqual(plan.sourceRect, rect)
        XCTAssertEqual(
            plan.makeStreamConfiguration().sourceRect,
            CGRect(x: 100, y: 50, width: 800, height: 600)
        )
    }

    func testSystemRegionUsesTheSameDisplayLocalSourceRectanglePolicy() throws {
        let rect = CaptureRect(x: 20, y: 40, width: 640, height: 480)
        let plan = try ScreenCaptureStreamPlan(
            configuration: CaptureConfiguration(
                source: .systemRegion(rect: rect),
                outputSize: .init(width: 1_280, height: 960)
            )
        )

        XCTAssertEqual(plan.sourceRect, rect)
        XCTAssertEqual(
            plan.makeStreamConfiguration().sourceRect,
            CGRect(x: 20, y: 40, width: 640, height: 480)
        )
    }

    func testRejectsQueueDepthOutsideScreenCaptureKitBounds() {
        let configuration = CaptureConfiguration(
            source: .display(id: 1),
            outputSize: .init(width: 1_920, height: 1_080)
        )

        XCTAssertThrowsError(
            try ScreenCaptureStreamPlan(configuration: configuration, queueDepth: 9)
        ) { error in
            XCTAssertEqual(error as? ScreenCaptureAdapterError, .invalidQueueDepth(9))
        }
    }
}
