import Foundation
import RecordCore
import XCTest

final class SessionSearchTests: XCTestCase {
    func testDateFilterUsesTheDisplayedLocalDayInsteadOfUTC() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: -6 * 3_600))
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-03T02:00:00Z"))
        XCTAssertTrue(
            SessionSearch.matches("2026-10-02", title: "Take", startedAt: date, calendar: calendar))
        XCTAssertFalse(
            SessionSearch.matches("2026-10-03", title: "Take", startedAt: date, calendar: calendar))
        XCTAssertTrue(
            SessionSearch.matches(" TAKE ", title: "Take", startedAt: date, calendar: calendar))
    }
}
