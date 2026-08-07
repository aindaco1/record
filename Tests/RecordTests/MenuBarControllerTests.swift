@testable import Record
import XCTest

@MainActor
final class MenuBarControllerTests: XCTestCase {
    func testNewKapMenuBarImageIsAProperlySizedTemplate() throws {
        let image = try XCTUnwrap(MenuBarController.menuBarImage())

        XCTAssertTrue(image.isTemplate)
        XCTAssertEqual(image.size.width, 16)
        XCTAssertEqual(image.size.height, 16)
    }
}
