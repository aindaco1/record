import RecordCore
import XCTest

final class CaptureConfigurationTests: XCTestCase {
    func testRequired4K60ConfigurationIsValid() throws {
        let configuration = CaptureConfiguration(
            source: .region(
                displayID: 1,
                rect: .init(x: 200, y: 20, width: 1_920, height: 1_080)
            ),
            outputSize: .init(width: 4_096, height: 2_160),
            frameRate: .fps60,
            showCursor: true,
            highlightClicks: true,
            camera: .init(deviceIdentifier: "camera", widthFraction: 0.25)
        )

        XCTAssertNoThrow(try configuration.validate())
    }

    func testRejectsOversizedAndNonFiniteGeometry() {
        let oversized = CaptureConfiguration(
            source: .display(id: 1),
            outputSize: .init(width: 5_120, height: 2_880)
        )
        let invalidRegion = CaptureConfiguration(
            source: .region(
                displayID: 1,
                rect: .init(x: .nan, y: 0, width: 100, height: 100)
            ),
            outputSize: .init(width: 1_920, height: 1_080)
        )

        XCTAssertThrowsError(try oversized.validate())
        XCTAssertThrowsError(try invalidRegion.validate()) { error in
            XCTAssertEqual(error as? CaptureConfiguration.ValidationError, .invalidRegion)
        }
    }

    func testRejectsOddOutputAndClickHighlightWithoutCursor() {
        let oddOutput = CaptureConfiguration(
            source: .display(id: 1),
            outputSize: .init(width: 1_919, height: 1_080)
        )
        let hiddenCursor = CaptureConfiguration(
            source: .display(id: 1),
            outputSize: .init(width: 1_920, height: 1_080),
            showCursor: false,
            highlightClicks: true
        )

        XCTAssertThrowsError(try oddOutput.validate()) { error in
            XCTAssertEqual(
                error as? CaptureConfiguration.ValidationError,
                .outputDimensionsMustBeEven(.init(width: 1_919, height: 1_080))
            )
        }
        XCTAssertThrowsError(try hiddenCursor.validate()) { error in
            XCTAssertEqual(
                error as? CaptureConfiguration.ValidationError,
                .clickHighlightRequiresCursor
            )
        }
    }

    func testApplicationCaptureRequiresDisplay() {
        let configuration = CaptureConfiguration(
            source: .application(bundleIdentifier: "com.example.Editor", displayID: 0),
            outputSize: .init(width: 1_920, height: 1_080)
        )

        XCTAssertThrowsError(try configuration.validate()) { error in
            XCTAssertEqual(
                error as? CaptureConfiguration.ValidationError,
                .invalidSourceIdentifier
            )
        }
    }

    func testRejectsInvalidCameraConfiguration() {
        let configuration = CaptureConfiguration(
            source: .window(id: 1),
            outputSize: .init(width: 1_920, height: 1_080),
            camera: .init(deviceIdentifier: "", widthFraction: 0.9)
        )

        XCTAssertThrowsError(try configuration.validate()) { error in
            XCTAssertEqual(
                error as? CaptureConfiguration.ValidationError,
                .invalidCameraIdentifier
            )
        }
    }
}
