import CoreGraphics
import Foundation
import RecordCore
@preconcurrency import ScreenCaptureKit

public struct ScreenCaptureScreenshotAdapter: Sendable {
    public init() {}

    public func captureDisplay(
        displayID: UInt32,
        privacy: CapturePrivacyConfiguration,
        showsCursor: Bool = false
    ) async throws -> CGImage {
        let resolved = try await ScreenCaptureContentResolver.screenshot(
            displayID: displayID,
            privacy: privacy
        )
        return try await capture(resolved, showsCursor: showsCursor)
    }

    public func captureRegion(
        displayID: UInt32,
        rect: CaptureRect,
        pointPixelScale: Double,
        privacy: CapturePrivacyConfiguration,
        showsCursor: Bool = false
    ) async throws -> CGImage {
        let resolved = try await ScreenCaptureContentResolver.screenshot(
            displayID: displayID,
            region: rect,
            pointPixelScale: pointPixelScale,
            privacy: privacy
        )
        return try await capture(resolved, showsCursor: showsCursor)
    }

    public func captureSelection(
        _ selection: SystemScreenCaptureSelection,
        privacy: CapturePrivacyConfiguration,
        showsCursor: Bool = false
    ) async throws -> CGImage {
        let resolved = try await ScreenCaptureContentResolver.screenshot(
            selection: selection,
            privacy: privacy
        )
        return try await capture(resolved, showsCursor: showsCursor)
    }

    private func capture(
        _ resolved: ResolvedScreenshotContent,
        showsCursor: Bool
    ) async throws -> CGImage {
        let configuration = SCStreamConfiguration()
        configuration.width = resolved.pixelSize.width
        configuration.height = resolved.pixelSize.height
        configuration.scalesToFit = false
        configuration.preservesAspectRatio = true
        configuration.showsCursor = showsCursor
        configuration.captureResolution = .best
        configuration.captureDynamicRange = .SDR
        configuration.includeChildWindows = true
        if resolved.style == .window {
            configuration.ignoreShadowsSingleWindow = false
        }
        if let rect = resolved.sourceRect {
            configuration.sourceRect = CGRect(
                x: rect.x,
                y: rect.y,
                width: rect.width,
                height: rect.height
            )
        }

        do {
            return try await SCScreenshotManager.captureImage(
                contentFilter: resolved.filter,
                configuration: configuration
            )
        } catch let error as ScreenCaptureAdapterError {
            throw error
        } catch {
            throw ScreenCaptureAdapterError.captureFailed(
                ScreenCaptureFailureMapper.failure(for: error)
            )
        }
    }
}
