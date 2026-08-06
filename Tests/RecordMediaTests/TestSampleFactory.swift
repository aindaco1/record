import CoreMedia
import CoreVideo
import RecordCapture

func makeTestSample(
    value: Int64,
    timescale: CMTimeScale = 60,
    kind: ScreenCaptureSampleKind = .screen
) throws -> ScreenCaptureSample {
    let presentationTime = CMTime(value: value, timescale: timescale)
    var pixelBuffer: CVPixelBuffer?
    let pixelStatus = CVPixelBufferCreate(
        kCFAllocatorDefault,
        2,
        2,
        kCVPixelFormatType_32BGRA,
        nil,
        &pixelBuffer
    )
    guard pixelStatus == kCVReturnSuccess, let pixelBuffer else {
        throw TestSampleError.creationFailed(pixelStatus)
    }

    var formatDescription: CMVideoFormatDescription?
    let formatStatus = CMVideoFormatDescriptionCreateForImageBuffer(
        allocator: kCFAllocatorDefault,
        imageBuffer: pixelBuffer,
        formatDescriptionOut: &formatDescription
    )
    guard formatStatus == noErr, let formatDescription else {
        throw TestSampleError.creationFailed(formatStatus)
    }

    var timing = CMSampleTimingInfo(
        duration: CMTime(value: 1, timescale: timescale),
        presentationTimeStamp: presentationTime,
        decodeTimeStamp: .invalid
    )
    var sampleBuffer: CMSampleBuffer?
    let sampleStatus = CMSampleBufferCreateReadyWithImageBuffer(
        allocator: kCFAllocatorDefault,
        imageBuffer: pixelBuffer,
        formatDescription: formatDescription,
        sampleTiming: &timing,
        sampleBufferOut: &sampleBuffer
    )
    guard sampleStatus == noErr, let sampleBuffer else {
        throw TestSampleError.creationFailed(sampleStatus)
    }
    return ScreenCaptureSample(
        kind: kind,
        timestamp: try ScreenCaptureTimestamp(validating: presentationTime),
        buffer: sampleBuffer
    )
}

private enum TestSampleError: Error {
    case creationFailed(OSStatus)
}
