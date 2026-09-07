import RecordCore
import XCTest

final class CaptureSelectionScopeTests: XCTestCase {
    func testDisplayBoundApplicationRetainsApplicationScope() {
        XCTAssertEqual(
            CaptureSelectionScope.resolve(
                reportedStyle: .display, includesApplications: true, includesWindows: false
            ),
            .application
        )
    }

    func testDisplayBoundWindowRetainsWindowScope() {
        XCTAssertEqual(
            CaptureSelectionScope.resolve(
                reportedStyle: .display, includesApplications: false, includesWindows: true
            ),
            .window
        )
    }

    func testUnrestrictedDisplayKeepsSharedDisplayPrivacyPolicy() {
        XCTAssertEqual(
            CaptureSelectionScope.resolve(
                reportedStyle: .display, includesApplications: false, includesWindows: false
            ),
            .display
        )
    }

    func testUninspectableDisplayBoundFilterFailsClosed() {
        XCTAssertNil(
            CaptureSelectionScope.resolve(
                reportedStyle: .display, includesApplications: nil, includesWindows: nil
            )
        )
    }

    func testExplicitNarrowScopesRemainUsableOnEarlierSystems() {
        for style: CaptureSelectionStyle in [.application, .window] {
            XCTAssertEqual(
                CaptureSelectionScope.resolve(
                    reportedStyle: style, includesApplications: nil, includesWindows: nil
                ),
                style
            )
        }
    }
}
