import Foundation
@testable import Record
import RecordCore
import XCTest

final class VideoCaptureProfileTests: XCTestCase {
    func testFiveKDisplayIsAspectFitToEven4KOutput() throws {
        let configuration = try VideoCaptureProfile.configuration(
            displayID: 42,
            pixelWidth: 5_120,
            pixelHeight: 2_880
        )

        XCTAssertEqual(configuration.source, .display(id: 42))
        XCTAssertEqual(configuration.outputSize, .init(width: 3_840, height: 2_160))
        XCTAssertEqual(configuration.frameRate, .fps30)
        XCTAssertTrue(configuration.showCursor)
        XCTAssertFalse(configuration.highlightClicks)
        XCTAssertTrue(configuration.audio.includeSystemAudio)
        XCTAssertTrue(configuration.audio.includeMicrophone)
    }

    func testOddNativeDimensionsAreRoundedDownWithoutUpscaling() throws {
        let configuration = try VideoCaptureProfile.configuration(
            displayID: 1,
            pixelWidth: 1_919,
            pixelHeight: 1_079
        )

        XCTAssertEqual(configuration.outputSize, .init(width: 1_918, height: 1_078))
    }

    func testUnavailableDisplayFailsClosed() {
        XCTAssertThrowsError(
            try VideoCaptureProfile.configuration(
                displayID: 0,
                pixelWidth: 1_920,
                pixelHeight: 1_080
            )
        ) { error in
            XCTAssertEqual(error as? VideoCaptureProfile.ProfileError, .displayUnavailable)
        }
    }

    func testRegionUsesDisplayLocalPointsAndRetinaPixelOutput() throws {
        let privacy = CapturePrivacyConfiguration(
            hideNotifications: false,
            hideMenuBar: true,
            hideDesktopItems: false
        )
        let selection = RegionSelection(
            displayID: 42,
            rect: .init(x: 100, y: 200, width: 800, height: 400),
            pointPixelScale: 2
        )

        let configuration = try VideoCaptureProfile.regionConfiguration(
            selection: selection,
            privacy: privacy
        )

        XCTAssertEqual(
            configuration.source,
            .region(displayID: 42, rect: selection.rect)
        )
        XCTAssertEqual(configuration.outputSize, .init(width: 1_600, height: 800))
        XCTAssertEqual(configuration.privacy, privacy)
        XCTAssertTrue(configuration.audio.includeSystemAudio)
        XCTAssertTrue(configuration.audio.includeMicrophone)
    }

    func testRegionRejectsAnInvalidDisplayScale() {
        XCTAssertThrowsError(
            try VideoCaptureProfile.regionConfiguration(
                selection: .init(
                    displayID: 1,
                    rect: .init(x: 0, y: 0, width: 100, height: 100),
                    pointPixelScale: .nan
                ),
                privacy: .init()
            )
        ) { error in
            XCTAssertEqual(error as? VideoCaptureProfile.ProfileError, .displayUnavailable)
        }
    }
}
