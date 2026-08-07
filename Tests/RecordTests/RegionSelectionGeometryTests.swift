import CoreGraphics
@testable import Record
import XCTest

final class RegionSelectionGeometryTests: XCTestCase {
    func testConvertsAppKitBottomLeftCoordinatesToDisplayLocalTopLeftCoordinates() throws {
        let rect = try RegionSelectionGeometry.captureRect(
            from: CGRect(x: 100, y: 200, width: 800, height: 400),
            viewSize: CGSize(width: 1_920, height: 1_080),
            contentSize: CGSize(width: 1_920, height: 1_080)
        )

        XCTAssertEqual(rect, .init(x: 100, y: 480, width: 800, height: 400))
    }

    func testScalesOverlayGeometryIntoLogicalDisplayCoordinates() throws {
        let rect = try RegionSelectionGeometry.captureRect(
            from: CGRect(x: 100, y: 100, width: 400, height: 300),
            viewSize: CGSize(width: 1_000, height: 500),
            contentSize: CGSize(width: 2_000, height: 1_000)
        )

        XCTAssertEqual(rect, .init(x: 200, y: 200, width: 800, height: 600))
    }

    func testRejectsTinyOrOutOfBoundsSelections() {
        XCTAssertThrowsError(
            try RegionSelectionGeometry.captureRect(
                from: CGRect(x: 0, y: 0, width: 8, height: 8),
                viewSize: CGSize(width: 100, height: 100),
                contentSize: CGSize(width: 100, height: 100)
            )
        )
        XCTAssertThrowsError(
            try RegionSelectionGeometry.captureRect(
                from: CGRect(x: 90, y: 90, width: 20, height: 20),
                viewSize: CGSize(width: 100, height: 100),
                contentSize: CGSize(width: 100, height: 100)
            )
        )
    }

    func testDisplayResolverPrefersPickerIdentifierAndUniqueGeometry() {
        let candidates = [
            RegionDisplayCandidate(
                displayID: 1,
                bounds: .init(x: 0, y: 0, width: 1_728, height: 1_117)
            ),
            RegionDisplayCandidate(
                displayID: 2,
                bounds: .init(x: 1_728, y: 0, width: 1_920, height: 1_080)
            ),
        ]

        XCTAssertEqual(
            RegionDisplayResolver.displayID(
                selectedDisplayID: 2,
                contentRect: .init(x: 0, y: 0, width: 1, height: 1),
                candidates: candidates
            ),
            2
        )
        XCTAssertEqual(
            RegionDisplayResolver.displayID(
                selectedDisplayID: nil,
                contentRect: .init(x: 0, y: 0, width: 1_728, height: 1_117),
                candidates: candidates
            ),
            1
        )
    }

    func testDisplayResolverUsesOnlyUnambiguousFallbacks() {
        let soleCandidate = RegionDisplayCandidate(
            displayID: 1,
            bounds: .init(x: 0, y: 0, width: 1_728, height: 1_117)
        )
        XCTAssertEqual(
            RegionDisplayResolver.displayID(
                selectedDisplayID: nil,
                contentRect: .init(x: 99, y: 99, width: 100, height: 100),
                candidates: [soleCandidate]
            ),
            1
        )
        XCTAssertNil(
            RegionDisplayResolver.displayID(
                selectedDisplayID: nil,
                contentRect: .init(x: 99, y: 99, width: 100, height: 100),
                candidates: [
                    soleCandidate,
                    .init(
                        displayID: 2,
                        bounds: .init(x: 1_728, y: 0, width: 1_920, height: 1_080)
                    ),
                ]
            )
        )
    }

    @MainActor
    func testBorderlessSelectionPanelCanBecomeKey() {
        let panel = RegionSelectionPanel(
            contentRect: .init(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        XCTAssertTrue(panel.canBecomeKey)
    }
}
