@testable import Record
import CoreServices
import XCTest

@MainActor
final class ApplicationLifecycleTests: XCTestCase {
    func testPublicationNotificationsDescribeTheRecordingMode() {
        XCTAssertEqual(
            AppController.readyNotificationTitle(for: .audioOnly),
            "Audio recording ready"
        )
        XCTAssertEqual(
            AppController.readyNotificationTitle(for: .screen),
            "Screen recording ready"
        )
        XCTAssertEqual(
            AppController.savedLocallyNotificationTitle(for: .audioOnly),
            "Audio recording saved locally"
        )
        XCTAssertEqual(
            AppController.savedLocallyNotificationTitle(for: .screen),
            "Screen recording saved locally"
        )
    }

    func testPrivacySettingsQuitIsTheOnlyRelaunchTrigger() {
        XCTAssertTrue(
            AppController.shouldRelaunchAfterPrivacySettingsQuit(
                eventClass: AEEventClass(kCoreEventClass),
                eventID: AEEventID(kAEQuitApplication),
                senderBundleIdentifier:
                    "com.apple.settings.PrivacySecurity.extension"
            )
        )
        XCTAssertTrue(
            AppController.shouldRelaunchAfterPrivacySettingsQuit(
                eventClass: AEEventClass(kCoreEventClass),
                eventID: AEEventID(kAEQuitApplication),
                senderBundleIdentifier: "com.apple.systempreferences"
            )
        )
        XCTAssertFalse(
            AppController.shouldRelaunchAfterPrivacySettingsQuit(
                eventClass: AEEventClass(kCoreEventClass),
                eventID: AEEventID(kAEQuitApplication),
                senderBundleIdentifier: "com.example.sender"
            )
        )
        XCTAssertFalse(
            AppController.shouldRelaunchAfterPrivacySettingsQuit(
                eventClass: AEEventClass(kCoreEventClass),
                eventID: AEEventID(kAEOpenApplication),
                senderBundleIdentifier:
                    "com.apple.settings.PrivacySecurity.extension"
            )
        )
    }
}
