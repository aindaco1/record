import RecordCapture
import RecordCore
import XCTest

final class ScreenCaptureSampleKindTests: XCTestCase {
    func testEveryCaptureKindMapsToTheCanonicalManifestKind() {
        XCTAssertEqual(ScreenCaptureSampleKind.screen.manifestTrackKind, .screen)
        XCTAssertEqual(ScreenCaptureSampleKind.systemAudio.manifestTrackKind, .systemAudio)
        XCTAssertEqual(ScreenCaptureSampleKind.microphone.manifestTrackKind, .microphone)
    }
}
