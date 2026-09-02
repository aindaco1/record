import CoreGraphics
import Foundation
import RecordCore
@preconcurrency import ScreenCaptureKit

/// Value-only geometry derived from a system content-picker result. Keeping
/// the planning step independent of framework-owned objects makes sizing and
/// region validation deterministic in ordinary CI.
public struct SystemScreenCaptureSelectionPlan: Equatable, Sendable {
    public let style: CaptureSelectionStyle
    public let contentRect: CaptureRect
    public let pointPixelScale: Double
    public let region: CaptureRect?
    public let source: CaptureSource
    public let outputSize: CaptureOutputSize
    public let nativePixelSize: ScreenshotPixelSize

    public init(
        style: CaptureSelectionStyle,
        contentRect: CaptureRect,
        pointPixelScale: Double,
        region: CaptureRect? = nil
    ) throws {
        guard Self.isValidContentRect(contentRect),
            pointPixelScale.isFinite, pointPixelScale > 0
        else {
            throw ScreenCaptureAdapterError.invalidSystemSelection
        }
        if let region {
            guard style == .display,
                Self.isValidRegion(region),
                region.x + region.width <= contentRect.width,
                region.y + region.height <= contentRect.height
            else {
                throw ScreenCaptureAdapterError.invalidSystemSelection
            }
        }

        let selectedWidth = region?.width ?? contentRect.width
        let selectedHeight = region?.height ?? contentRect.height
        let nativePixelSize = try ScreenshotPixelSize(
            width: Int((selectedWidth * pointPixelScale).rounded(.up)),
            height: Int((selectedHeight * pointPixelScale).rounded(.up))
        )
        guard
            let outputSize = CaptureOutputSize.boundedForCapture(
                pixelWidth: nativePixelSize.width,
                pixelHeight: nativePixelSize.height
            )
        else {
            throw ScreenCaptureAdapterError.invalidSystemSelection
        }

        self.style = style
        self.contentRect = contentRect
        self.pointPixelScale = pointPixelScale
        self.region = region
        self.nativePixelSize = nativePixelSize
        source =
            region.map(CaptureSource.systemRegion)
            ?? .systemSelection(style: style)
        self.outputSize = outputSize
    }

    private static func isValidContentRect(_ rect: CaptureRect) -> Bool {
        rect.x.isFinite && rect.y.isFinite
            && rect.width.isFinite && rect.height.isFinite
            && rect.width > 0 && rect.height > 0
    }

    private static func isValidRegion(_ rect: CaptureRect) -> Bool {
        isValidContentRect(rect) && rect.x >= 0 && rect.y >= 0
    }
}

/// Holds the opaque system-owned filter only for the lifetime of a pending or
/// active recording. Window titles and source identifiers are never encoded or
/// written to preferences.
public final class SystemScreenCaptureSelection: @unchecked Sendable {
    public let plan: SystemScreenCaptureSelectionPlan
    public let selectedDisplayID: UInt32?
    let contentFilter: SCContentFilter

    public init(contentFilter: SCContentFilter, region: CaptureRect? = nil) throws {
        let style: CaptureSelectionStyle
        switch contentFilter.style {
        case .display:
            style = .display
        case .application:
            style = .application
        case .window:
            style = .window
        case .none:
            throw ScreenCaptureAdapterError.invalidSystemSelection
        @unknown default:
            throw ScreenCaptureAdapterError.invalidSystemSelection
        }

        let rect = contentFilter.contentRect
        plan = try SystemScreenCaptureSelectionPlan(
            style: style,
            contentRect: .init(
                x: rect.origin.x,
                y: rect.origin.y,
                width: rect.width,
                height: rect.height
            ),
            pointPixelScale: Double(contentFilter.pointPixelScale),
            region: region
        )
        if #available(macOS 15.2, *), style == .display {
            selectedDisplayID = contentFilter.includedDisplays.first?.displayID
        } else {
            selectedDisplayID = nil
        }
        self.contentFilter = contentFilter
    }

    public func selecting(region: CaptureRect) throws -> SystemScreenCaptureSelection {
        try SystemScreenCaptureSelection(contentFilter: contentFilter, region: region)
    }

    public func configuration(
        frameRate: CaptureFrameRate = .fps30,
        showCursor: Bool = true,
        highlightClicks: Bool = false,
        audio: CaptureAudioConfiguration = .init(),
        privacy: CapturePrivacyConfiguration = .init()
    ) throws -> CaptureConfiguration {
        let configuration = CaptureConfiguration(
            source: plan.source,
            outputSize: plan.outputSize,
            frameRate: frameRate,
            showCursor: showCursor,
            highlightClicks: highlightClicks,
            audio: audio,
            privacy: privacy
        )
        try configuration.validate()
        return configuration
    }
}
