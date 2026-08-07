import RecordCapture
import RecordCore
import XCTest

final class ScreenCaptureSourceInventoryTests: XCTestCase {
    private let inventory = ScreenCaptureSourceInventory(
        displays: [.init(id: 1, width: 2_560, height: 1_440)],
        applicationBundleIdentifiers: ["com.example.Editor"],
        windowIDs: [42]
    )

    func testResolvesEverySupportedSourceWithoutFallbacks() throws {
        let sources: [CaptureSource] = [
            .display(id: 1),
            .application(bundleIdentifier: "com.example.Editor", displayID: 1),
            .window(id: 42),
            .region(
                displayID: 1,
                rect: .init(x: 100, y: 50, width: 800, height: 600)
            ),
        ]

        for source in sources {
            XCTAssertEqual(try inventory.resolve(source), source)
        }
    }

    func testRejectsMissingSourceInsteadOfChoosingAnother() {
        let source = CaptureSource.application(
            bundleIdentifier: "com.example.Missing",
            displayID: 1
        )

        XCTAssertThrowsError(try inventory.resolve(source)) { error in
            XCTAssertEqual(
                error as? ScreenCaptureAdapterError,
                .sourceUnavailable(source)
            )
        }
    }

    func testRejectsRegionOutsideSelectedDisplay() {
        let rect = CaptureRect(x: 2_400, y: 0, width: 400, height: 400)

        XCTAssertThrowsError(
            try inventory.resolve(.region(displayID: 1, rect: rect))
        ) { error in
            XCTAssertEqual(
                error as? ScreenCaptureAdapterError,
                .regionOutsideDisplay(displayID: 1, rect: rect)
            )
        }
    }

    func testSystemSelectionsRequireTheirOpaquePickerFilter() {
        XCTAssertThrowsError(
            try inventory.resolve(.systemSelection(style: .window))
        ) { error in
            XCTAssertEqual(
                error as? ScreenCaptureAdapterError,
                .systemSelectionRequired
            )
        }
    }
}
