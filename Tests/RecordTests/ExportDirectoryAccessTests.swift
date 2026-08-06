import Foundation
@testable import Record
import XCTest

@MainActor
final class ExportDirectoryAccessTests: XCTestCase {
    func testFirstRunSuggestsDesktopWithoutClaimingAccess() throws {
        let defaults = try makeDefaults()
        let access = ExportDirectoryAccess(
            defaults: defaults,
            userHome: URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        )

        XCTAssertEqual(access.suggestedDirectory.path, "/Users/tester/Desktop")
        XCTAssertNil(try access.restore())
    }

    func testMalformedBookmarkFailsClosedAndCanBeForgotten() throws {
        let defaults = try makeDefaults()
        defaults.set(Data("not a bookmark".utf8), forKey: ExportDirectoryAccess.bookmarkKey)
        let access = ExportDirectoryAccess(
            defaults: defaults,
            userHome: URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        )

        XCTAssertThrowsError(try access.restore())
        access.forgetStoredSelection()
        XCTAssertNil(defaults.data(forKey: ExportDirectoryAccess.bookmarkKey))
    }

    private func makeDefaults() throws -> UserDefaults {
        let suite = "com.aindaco.record.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suite)
        }
        return defaults
    }
}
