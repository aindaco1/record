@preconcurrency import ScreenCaptureKit
@testable import Record
import XCTest

private struct PickerTestError: Error {}

private struct SendableSharingPicker: @unchecked Sendable {
    let value: SCContentSharingPicker
}

final class SystemScreenCapturePickerTests: XCTestCase {
    func testCancellationCallbackCanArriveOffMainActor() async {
        let (subject, picker) = await MainActor.run {
            (
                SystemScreenCapturePicker(),
                SendableSharingPicker(value: SCContentSharingPicker.shared)
            )
        }
        let callbackReturned = expectation(description: "picker callback returned")

        DispatchQueue.global().async {
            subject.contentSharingPicker(picker.value, didCancelFor: nil)
            callbackReturned.fulfill()
        }

        await fulfillment(of: [callbackReturned], timeout: 1)
    }

    func testObserverFailureCallbackCanArriveOffMainActor() async {
        let subject = await MainActor.run { SystemScreenCapturePicker() }
        let callbackReturned = expectation(description: "picker callback returned")

        DispatchQueue.global().async {
            subject.contentSharingPickerStartDidFailWithError(PickerTestError())
            callbackReturned.fulfill()
        }

        await fulfillment(of: [callbackReturned], timeout: 1)
    }
}
