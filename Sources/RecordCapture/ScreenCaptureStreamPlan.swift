import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
import RecordCore
import ScreenCaptureKit

public struct ScreenCaptureStreamPlan: Equatable, Sendable {
    public enum PixelFormat: Equatable, Sendable {
        /// Hardware-encoder-friendly SDR video range; preferred for performance.
        case videoRange420
        /// Required by ScreenCaptureKit's native click highlighting.
        case bgra
    }

    public static let defaultQueueDepth = 5
    public static let allowedQueueDepth = 3...8

    public let source: CaptureSource
    public let width: Int
    public let height: Int
    public let framesPerSecond: Int
    public let queueDepth: Int
    public let pixelFormat: PixelFormat
    public let showsCursor: Bool
    public let showsMouseClicks: Bool
    public let capturesSystemAudio: Bool
    public let capturesMicrophone: Bool
    public let sourceRect: CaptureRect?

    public init(
        configuration: CaptureConfiguration,
        queueDepth: Int = Self.defaultQueueDepth
    ) throws {
        try configuration.validate()
        guard Self.allowedQueueDepth.contains(queueDepth) else {
            throw ScreenCaptureAdapterError.invalidQueueDepth(queueDepth)
        }

        source = configuration.source
        width = configuration.outputSize.width
        height = configuration.outputSize.height
        framesPerSecond = configuration.frameRate.rawValue
        self.queueDepth = queueDepth
        pixelFormat = configuration.highlightClicks ? .bgra : .videoRange420
        showsCursor = configuration.showCursor
        showsMouseClicks = configuration.highlightClicks
        capturesSystemAudio = configuration.audio.includeSystemAudio
        capturesMicrophone = configuration.audio.includeMicrophone
        if case .region(_, let rect) = configuration.source {
            sourceRect = rect
        } else {
            sourceRect = nil
        }
    }

    public func makeStreamConfiguration() -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        configuration.width = width
        configuration.height = height
        configuration.minimumFrameInterval = CMTime(
            value: 1,
            timescale: CMTimeScale(framesPerSecond)
        )
        configuration.queueDepth = queueDepth
        configuration.scalesToFit = true
        configuration.preservesAspectRatio = true
        configuration.showsCursor = showsCursor
        configuration.showMouseClicks = showsMouseClicks
        configuration.capturesAudio = capturesSystemAudio
        configuration.captureMicrophone = capturesMicrophone
        configuration.sampleRate = 48_000
        configuration.channelCount = 2
        configuration.excludesCurrentProcessAudio = true
        configuration.captureResolution = .best
        configuration.captureDynamicRange = .SDR
        configuration.includeChildWindows = true

        if let sourceRect {
            configuration.sourceRect = CGRect(
                x: sourceRect.x,
                y: sourceRect.y,
                width: sourceRect.width,
                height: sourceRect.height
            )
        }

        switch pixelFormat {
        case .videoRange420:
            configuration.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
            configuration.colorMatrix = CGDisplayStream.yCbCrMatrix_ITU_R_709_2
            configuration.colorSpaceName = CGColorSpace.itur_709
        case .bgra:
            configuration.pixelFormat = kCVPixelFormatType_32BGRA
            configuration.colorSpaceName = CGColorSpace.sRGB
        }
        return configuration
    }
}
