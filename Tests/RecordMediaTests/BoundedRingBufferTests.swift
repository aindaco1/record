@testable import RecordMedia
import XCTest

final class BoundedRingBufferTests: XCTestCase {
    func testEvictsOldestWithoutGrowingPastCapacity() {
        var buffer = BoundedRingBuffer<Int>(capacity: 2)

        XCTAssertNil(buffer.appendDroppingOldest(1))
        XCTAssertNil(buffer.appendDroppingOldest(2))
        XCTAssertEqual(buffer.appendDroppingOldest(3), 1)
        XCTAssertEqual(buffer.count, 2)
        XCTAssertEqual(buffer.popFirst(), 2)
        XCTAssertEqual(buffer.popFirst(), 3)
        XCTAssertNil(buffer.popFirst())
    }

    func testRemoveAllReleasesEverySlotAndPreservesCapacity() {
        var buffer = BoundedRingBuffer<Int>(capacity: 2)
        buffer.appendDroppingOldest(1)
        buffer.appendDroppingOldest(2)

        XCTAssertEqual(buffer.removeAll(), 2)
        XCTAssertEqual(buffer.count, 0)
        XCTAssertNil(buffer.appendDroppingOldest(3))
        XCTAssertEqual(buffer.popFirst(), 3)
    }
}
