@testable import Record
import Carbon
import RecordCore
import XCTest

final class GlobalScreenshotShortcutRegistrarTests: XCTestCase {
    func testCarbonPlanPreservesAllSupportedModifiers() {
        let flags = CarbonScreenshotShortcutPlan.modifiers([
            .command, .shift, .option, .control,
        ])

        XCTAssertNotEqual(flags & UInt32(cmdKey), 0)
        XCTAssertNotEqual(flags & UInt32(shiftKey), 0)
        XCTAssertNotEqual(flags & UInt32(optionKey), 0)
        XCTAssertNotEqual(flags & UInt32(controlKey), 0)
    }

    func testIdentifiersRoundTripAndUnknownIdentifiersFailClosed() {
        for kind in ScreenshotCaptureKind.allCases {
            XCTAssertEqual(
                CarbonScreenshotShortcutPlan.kind(
                    for: CarbonScreenshotShortcutPlan.identifier(for: kind)
                ),
                kind
            )
        }
        XCTAssertNil(CarbonScreenshotShortcutPlan.kind(for: 99))
    }
}
