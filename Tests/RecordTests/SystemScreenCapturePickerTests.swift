@preconcurrency import ScreenCaptureKit
@testable import Record
import XCTest

private struct PickerTestError: Error {}

private struct SendableSharingPicker: @unchecked Sendable {
    let value: SCContentSharingPicker
}

final class SystemScreenCapturePickerTests: XCTestCase {
    func testScreenshotPickerAllowsOnlyApplicationsAndWindows() {
        let modes = SystemScreenCapturePickerMode.windowOrApplication.allowedPickerModes

        XCTAssertTrue(modes.contains(.singleApplication))
        XCTAssertTrue(modes.contains(.singleWindow))
        XCTAssertFalse(modes.contains(.singleDisplay))
    }

    func testScreenshotPickerCanIncludeRecordWhileHidingNotifications() {
        let excluded = SystemScreenCapturePicker.excludedBundleIdentifiers(
            privacy: .init(),
            ownBundleIdentifier: "com.aindaco.record",
            ownApplicationPolicy: .include
        )

        XCTAssertFalse(excluded.contains("com.aindaco.record"))
        XCTAssertTrue(excluded.contains("com.apple.notificationcenterui"))
    }

    func testRecordingPickerContinuesToExcludeRecord() {
        let excluded = SystemScreenCapturePicker.excludedBundleIdentifiers(
            privacy: .init(),
            ownBundleIdentifier: "com.aindaco.record",
            ownApplicationPolicy: .exclude
        )

        XCTAssertTrue(excluded.contains("com.aindaco.record"))
    }

    func testCancellationCallbackCanArriveOffMainActor() async {
        let picker = SendableSharingPicker(value: SCContentSharingPicker.shared)
        let callbackReturned = expectation(description: "picker callback returned")
        let cancellationDelivered = expectation(description: "cancellation delivered")
        let subject = SystemScreenCapturePickerObserverProxy(
            onCancel: { cancellationDelivered.fulfill() },
            onFailure: {},
            onSelection: { _ in }
        )

        DispatchQueue.global().async {
            subject.contentSharingPicker(picker.value, didCancelFor: nil)
            callbackReturned.fulfill()
        }

        await fulfillment(of: [callbackReturned, cancellationDelivered], timeout: 1)
    }

    func testObserverFailureCallbackCanArriveOffMainActor() async {
        let callbackReturned = expectation(description: "picker callback returned")
        let failureDelivered = expectation(description: "failure delivered")
        let subject = SystemScreenCapturePickerObserverProxy(
            onCancel: {},
            onFailure: { failureDelivered.fulfill() },
            onSelection: { _ in }
        )

        DispatchQueue.global().async {
            subject.contentSharingPickerStartDidFailWithError(PickerTestError())
            callbackReturned.fulfill()
        }

        await fulfillment(of: [callbackReturned, failureDelivered], timeout: 1)
    }
}
