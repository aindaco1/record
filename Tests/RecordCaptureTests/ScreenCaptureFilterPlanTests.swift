import RecordCapture
import RecordCore
import XCTest

final class ScreenCaptureFilterPlanTests: XCTestCase {
    func testPrivacyDefaultsExcludeOnlyCaptureSurfacesAndPreserveFinderWindows() {
        let plan = ScreenCaptureFilterPlan(
            privacy: .init(),
            ownBundleIdentifier: "com.aindaco.record",
            availableApplicationBundleIdentifiers: [
                "com.aindaco.record",
                "com.apple.finder",
                "com.apple.notificationcenterui",
                "com.example.Editor",
            ],
            windows: [
                .init(
                    id: 1,
                    ownerBundleIdentifier: "com.apple.finder",
                    layer: -2_147_483_603
                ),
                .init(id: 2, ownerBundleIdentifier: "com.apple.finder", layer: 0),
                .init(id: 3, ownerBundleIdentifier: "com.example.Editor", layer: 0),
            ]
        )

        XCTAssertFalse(plan.includeMenuBar)
        XCTAssertEqual(
            plan.excludedApplicationBundleIdentifiers,
            [
                "com.aindaco.record",
                "com.apple.finder",
                "com.apple.notificationcenterui",
            ]
        )
        XCTAssertEqual(plan.exceptedWindowIDs, [2])
    }

    func testDisabledPrivacyStillExcludesRecordWithoutFinderExceptions() {
        let plan = ScreenCaptureFilterPlan(
            privacy: .init(
                hideNotifications: false,
                hideMenuBar: false,
                hideDesktopItems: false
            ),
            ownBundleIdentifier: "com.aindaco.record",
            availableApplicationBundleIdentifiers: [
                "com.aindaco.record", "com.apple.finder", "com.apple.notificationcenterui",
            ],
            windows: [
                .init(id: 1, ownerBundleIdentifier: "com.apple.finder", layer: 0)
            ]
        )

        XCTAssertTrue(plan.includeMenuBar)
        XCTAssertEqual(plan.excludedApplicationBundleIdentifiers, ["com.aindaco.record"])
        XCTAssertTrue(plan.exceptedWindowIDs.isEmpty)
    }

    func testScreenshotPolicyIncludesRecordWithoutWeakeningOtherPrivacyFilters() {
        let plan = ScreenCaptureFilterPlan(
            privacy: .init(),
            ownBundleIdentifier: "com.aindaco.record",
            ownApplicationPolicy: .include,
            availableApplicationBundleIdentifiers: [
                "com.aindaco.record",
                "com.apple.finder",
                "com.apple.notificationcenterui",
            ],
            windows: [
                .init(id: 1, ownerBundleIdentifier: "com.apple.finder", layer: -1),
                .init(id: 2, ownerBundleIdentifier: "com.apple.finder", layer: 0),
            ]
        )

        XCTAssertFalse(plan.excludedApplicationBundleIdentifiers.contains("com.aindaco.record"))
        XCTAssertTrue(
            plan.excludedApplicationBundleIdentifiers.contains("com.apple.notificationcenterui")
        )
        XCTAssertTrue(plan.excludedApplicationBundleIdentifiers.contains("com.apple.finder"))
        XCTAssertEqual(plan.exceptedWindowIDs, [2])
    }

    func testDesktopClassifierDoesNotDependOnWindowTitlesOrCoordinates() {
        XCTAssertTrue(
            ScreenCaptureFilterPlan.isDesktopWindow(
                .init(id: 1, ownerBundleIdentifier: "com.apple.finder", layer: -1)
            )
        )
        XCTAssertFalse(
            ScreenCaptureFilterPlan.isDesktopWindow(
                .init(id: 2, ownerBundleIdentifier: "com.apple.finder", layer: 0)
            )
        )
        XCTAssertFalse(
            ScreenCaptureFilterPlan.isDesktopWindow(
                .init(id: 3, ownerBundleIdentifier: "com.example.Editor", layer: -1)
            )
        )
    }
}
