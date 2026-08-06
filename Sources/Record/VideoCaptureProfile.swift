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
        let size = boundedEvenSize(width: pixelWidth, height: pixelHeight)
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

    /// Preserve the display aspect ratio while fitting the hardware writer's
    /// 4K bound. Even dimensions avoid chroma-subsampling padding and copies.
    static func boundedEvenSize(width: Int, height: Int) -> CaptureOutputSize {
        let scale = min(
            1,
            min(4_096 / Double(width), 2_160 / Double(height))
        )
        let scaledWidth = max(16, Int((Double(width) * scale).rounded(.down)))
        let scaledHeight = max(16, Int((Double(height) * scale).rounded(.down)))
        return CaptureOutputSize(
            width: scaledWidth - scaledWidth % 2,
            height: scaledHeight - scaledHeight % 2
        )
    }
}
