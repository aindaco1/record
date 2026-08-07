@testable import Record
import CoreAudio
import XCTest

final class PreparedSystemAudioTapTests: XCTestCase {
    func testUnconsumedTapIsDestroyedExactlyOnce() {
        let destruction = TapDestructionRecorder()

        do {
            _ = PreparedSystemAudioTap(
                handle: .init(id: 17, uuid: UUID()),
                destroy: { destruction.record($0) }
            )
        }

        XCTAssertEqual(destruction.tapIDs, [17])
    }

    func testConsumedTapTransfersOwnershipWithoutDestroyingIt() {
        let destruction = TapDestructionRecorder()
        var tap: PreparedSystemAudioTap? = PreparedSystemAudioTap(
            handle: .init(id: 23, uuid: UUID()),
            destroy: { destruction.record($0) }
        )

        XCTAssertEqual(tap?.consume()?.id, 23)
        XCTAssertNil(tap?.consume())
        tap = nil

        XCTAssertEqual(destruction.tapIDs, [])
    }
}

private final class TapDestructionRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedTapIDs: [AudioObjectID] = []

    var tapIDs: [AudioObjectID] {
        lock.withLock { recordedTapIDs }
    }

    func record(_ tapID: AudioObjectID) {
        lock.withLock { recordedTapIDs.append(tapID) }
    }
}
