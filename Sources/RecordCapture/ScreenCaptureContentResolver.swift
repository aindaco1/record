import Foundation
import RecordCore
@preconcurrency import ScreenCaptureKit

struct ResolvedScreenshotContent: @unchecked Sendable {
    let filter: SCContentFilter
    let pixelSize: ScreenshotPixelSize
    let sourceRect: CaptureRect?
    let style: CaptureSelectionStyle
}

enum ScreenCaptureContentResolver {
    static func filter(for configuration: CaptureConfiguration) async throws -> SCContentFilter {
        let content = try await shareableContent()
        let inventory = inventory(from: content)
        try inventory.resolve(configuration.source)
        return try filter(for: configuration, in: content)
    }

    static func filter(
        for selection: SystemScreenCaptureSelection,
        configuration: CaptureConfiguration
    ) async throws -> SCContentFilter {
        guard configuration.source == selection.plan.source,
            configuration.outputSize == selection.plan.outputSize
        else {
            throw ScreenCaptureAdapterError.systemSelectionMismatch
        }
        guard selection.plan.style == .display else {
            return selection.contentFilter
        }

        let content = try await shareableContent()
        let display = try selectedDisplay(for: selection, in: content, source: configuration.source)
        return displayFilter(
            display: display,
            privacy: configuration.privacy,
            content: content
        )
    }

    static func screenshot(
        displayID: UInt32,
        region: CaptureRect? = nil,
        pointPixelScale: Double? = nil,
        privacy: CapturePrivacyConfiguration
    ) async throws -> ResolvedScreenshotContent {
        let content = try await shareableContent()
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw ScreenCaptureAdapterError.sourceUnavailable(.display(id: displayID))
        }

        let pixelSize: ScreenshotPixelSize
        if let region {
            guard let pointPixelScale,
                pointPixelScale.isFinite,
                pointPixelScale > 0,
                region.x >= 0,
                region.y >= 0,
                region.width > 0,
                region.height > 0,
                region.x + region.width <= display.frame.width,
                region.y + region.height <= display.frame.height
            else {
                throw ScreenCaptureAdapterError.regionOutsideDisplay(
                    displayID: displayID,
                    rect: region
                )
            }
            pixelSize = try ScreenshotPixelSize(
                width: Int((region.width * pointPixelScale).rounded(.up)),
                height: Int((region.height * pointPixelScale).rounded(.up))
            )
        } else {
            pixelSize = try ScreenshotPixelSize(width: display.width, height: display.height)
        }

        return ResolvedScreenshotContent(
            filter: displayFilter(
                display: display,
                privacy: privacy,
                content: content,
                ownApplicationPolicy: .include
            ),
            pixelSize: pixelSize,
            sourceRect: region,
            style: .display
        )
    }

    static func screenshot(
        selection: SystemScreenCaptureSelection,
        privacy: CapturePrivacyConfiguration
    ) async throws -> ResolvedScreenshotContent {
        let filter: SCContentFilter
        if selection.plan.style == .display {
            let content = try await shareableContent()
            let display = try selectedDisplay(
                for: selection,
                in: content,
                source: selection.plan.source
            )
            filter = displayFilter(
                display: display,
                privacy: privacy,
                content: content,
                ownApplicationPolicy: .include
            )
        } else {
            filter = selection.contentFilter
        }

        return ResolvedScreenshotContent(
            filter: filter,
            pixelSize: selection.plan.nativePixelSize,
            sourceRect: selection.plan.region,
            style: selection.plan.style
        )
    }

    private static func shareableContent() async throws -> SCShareableContent {
        try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: false
        )
    }

    private static func selectedDisplay(
        for selection: SystemScreenCaptureSelection,
        in content: SCShareableContent,
        source: CaptureSource
    ) throws -> SCDisplay {
        let selectedRect = selection.plan.contentRect
        let tolerance = 1.0
        guard
            let display = content.displays.first(where: { display in
                if let selectedDisplayID = selection.selectedDisplayID {
                    return display.displayID == selectedDisplayID
                }
                return abs(display.frame.origin.x - selectedRect.x) <= tolerance
                    && abs(display.frame.origin.y - selectedRect.y) <= tolerance
                    && abs(display.frame.width - selectedRect.width) <= tolerance
                    && abs(display.frame.height - selectedRect.height) <= tolerance
            })
        else {
            throw ScreenCaptureAdapterError.sourceUnavailable(source)
        }
        return display
    }

    private static func inventory(
        from content: SCShareableContent
    ) -> ScreenCaptureSourceInventory {
        ScreenCaptureSourceInventory(
            displays: content.displays.map {
                .init(id: $0.displayID, width: $0.width, height: $0.height)
            },
            applicationBundleIdentifiers: Set(content.applications.map(\.bundleIdentifier)),
            windowIDs: Set(content.windows.map(\.windowID))
        )
    }

    private static func filter(
        for configuration: CaptureConfiguration,
        in content: SCShareableContent
    ) throws -> SCContentFilter {
        let source = configuration.source
        switch source {
        case .display(let id), .region(let id, _):
            guard let display = content.displays.first(where: { $0.displayID == id }) else {
                throw ScreenCaptureAdapterError.sourceUnavailable(source)
            }
            return displayFilter(
                display: display,
                privacy: configuration.privacy,
                content: content
            )

        case .application(let bundleIdentifier, let displayID):
            guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
                throw ScreenCaptureAdapterError.sourceUnavailable(source)
            }
            let applications = content.applications.filter {
                $0.bundleIdentifier == bundleIdentifier
            }
            guard !applications.isEmpty else {
                throw ScreenCaptureAdapterError.sourceUnavailable(source)
            }
            return SCContentFilter(
                display: display,
                including: applications,
                exceptingWindows: []
            )

        case .window(let id):
            guard let window = content.windows.first(where: { $0.windowID == id }) else {
                throw ScreenCaptureAdapterError.sourceUnavailable(source)
            }
            return SCContentFilter(desktopIndependentWindow: window)

        case .systemSelection, .systemRegion:
            throw ScreenCaptureAdapterError.systemSelectionRequired
        }
    }

    private static func displayFilter(
        display: SCDisplay,
        privacy: CapturePrivacyConfiguration,
        content: SCShareableContent,
        ownApplicationPolicy: ScreenCaptureFilterPlan.OwnApplicationPolicy = .exclude
    ) -> SCContentFilter {
        let plan = ScreenCaptureFilterPlan(
            privacy: privacy,
            ownBundleIdentifier: Bundle.main.bundleIdentifier,
            ownApplicationPolicy: ownApplicationPolicy,
            availableApplicationBundleIdentifiers: Set(
                content.applications.map(\.bundleIdentifier)
            ),
            windows: content.windows.map {
                .init(
                    id: $0.windowID,
                    ownerBundleIdentifier: $0.owningApplication?.bundleIdentifier,
                    layer: $0.windowLayer
                )
            }
        )
        let excludedApplications = content.applications.filter {
            plan.excludedApplicationBundleIdentifiers.contains($0.bundleIdentifier)
        }
        let exceptedWindows = content.windows.filter {
            plan.exceptedWindowIDs.contains($0.windowID)
        }
        let filter = SCContentFilter(
            display: display,
            excludingApplications: excludedApplications,
            exceptingWindows: exceptedWindows
        )
        filter.includeMenuBar = plan.includeMenuBar
        return filter
    }
}
