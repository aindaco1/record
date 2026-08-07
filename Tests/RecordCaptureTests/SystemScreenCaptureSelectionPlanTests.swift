import RecordCapture
import RecordCore
import XCTest

final class SystemScreenCaptureSelectionPlanTests: XCTestCase {
    func testApplicationSelectionDerivesBoundedPixelOutputWithoutAnIdentifier() throws {
        let plan = try SystemScreenCaptureSelectionPlan(
            style: .application,
            contentRect: .init(x: 10, y: 20, width: 2_560, height: 1_440),
            pointPixelScale: 2
        )

        XCTAssertEqual(plan.source, .systemSelection(style: .application))
        XCTAssertEqual(plan.outputSize, .init(width: 3_840, height: 2_160))
    }

    func testRegionUsesItsOwnGeometryForOutputSize() throws {
        let region = CaptureRect(x: 100, y: 50, width: 800, height: 600)
        let plan = try SystemScreenCaptureSelectionPlan(
            style: .display,
            contentRect: .init(x: 0, y: 0, width: 1_920, height: 1_080),
            pointPixelScale: 2,
            region: region
        )

        XCTAssertEqual(plan.source, .systemRegion(rect: region))
        XCTAssertEqual(plan.outputSize, .init(width: 1_600, height: 1_200))
    }

    func testRejectsRegionForANonDisplayOrOutsideTheDisplay() {
        let content = CaptureRect(x: 0, y: 0, width: 1_000, height: 800)
        XCTAssertThrowsError(
            try SystemScreenCaptureSelectionPlan(
                style: .window,
                contentRect: content,
                pointPixelScale: 1,
                region: .init(x: 0, y: 0, width: 100, height: 100)
            )
        )
        XCTAssertThrowsError(
            try SystemScreenCaptureSelectionPlan(
                style: .display,
                contentRect: content,
                pointPixelScale: 1,
                region: .init(x: 900, y: 700, width: 200, height: 200)
            )
        )
    }
}
