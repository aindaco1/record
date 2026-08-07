@testable import Record
import CoreServices
import XCTest

@MainActor
final class ApplicationLifecycleTests: XCTestCase {
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
