import CoreGraphics
import Foundation
import RecordCore

enum VideoCaptureProfile {
    enum ProfileError: Error, Equatable {
        case displayUnavailable
    }

    static func mainDisplayConfiguration() throws -> CaptureConfiguration {
        let displayID = CGMainDisplayID()
        let width = CGDisplayPixelsWide(displayID)
        let height = CGDisplayPixelsHigh(displayID)
        guard displayID > 0, width > 0, height > 0 else {
            throw ProfileError.displayUnavailable
        }
        return try configuration(
            displayID: displayID,
            pixelWidth: width,
            pixelHeight: height
        )
    }

    static func configuration(
        displayID: UInt32,
        pixelWidth: Int,
        pixelHeight: Int
    ) throws -> CaptureConfiguration {
        guard displayID > 0, pixelWidth > 0, pixelHeight > 0 else {
            throw ProfileError.displayUnavailable
        }
        guard
            let size = CaptureOutputSize.boundedForCapture(
                pixelWidth: pixelWidth,
                pixelHeight: pixelHeight
            )
        else {
            throw ProfileError.displayUnavailable
        }
        let configuration = CaptureConfiguration(
            source: .display(id: displayID),
            outputSize: size,
            frameRate: .fps30,
            showCursor: true,
            highlightClicks: false,
            audio: .init(includeSystemAudio: true, includeMicrophone: true)
        )
        try configuration.validate()
        return configuration
    }

    static func regionConfiguration(
        selection: RegionSelection,
        privacy: CapturePrivacyConfiguration
    ) throws -> CaptureConfiguration {
        guard selection.displayID > 0,
            selection.pointPixelScale.isFinite,
            selection.pointPixelScale > 0
        else {
            throw ProfileError.displayUnavailable
        }
        guard
            let size = CaptureOutputSize.boundedForCapture(
                pixelWidth: Int(
                    (selection.rect.width * selection.pointPixelScale).rounded(.up)
                ),
                pixelHeight: Int(
                    (selection.rect.height * selection.pointPixelScale).rounded(.up)
                )
            )
        else {
            throw ProfileError.displayUnavailable
        }
        let configuration = CaptureConfiguration(
            source: .region(displayID: selection.displayID, rect: selection.rect),
            outputSize: size,
            frameRate: .fps30,
            showCursor: true,
            highlightClicks: false,
            audio: .init(includeSystemAudio: true, includeMicrophone: true),
            privacy: privacy
        )
        try configuration.validate()
        return configuration
    }

    /// Preserve the display aspect ratio while fitting the hardware writer's
    /// 4K bound. Even dimensions avoid chroma-subsampling padding and copies.
    static func boundedEvenSize(width: Int, height: Int) -> CaptureOutputSize {
        CaptureOutputSize.boundedForCapture(
            pixelWidth: width,
            pixelHeight: height
        ) ?? .init(width: 16, height: 16)
    }
}
