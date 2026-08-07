import AudioToolbox
import CoreMedia
import CoreVideo
import RecordCapture

func makeTestSample(
    value: Int64,
    timescale: CMTimeScale = 60,
    kind: ScreenCaptureSampleKind = .screen,
    width: Int = 2,
    height: Int = 2
) throws -> ScreenCaptureSample {
    let presentationTime = CMTime(value: value, timescale: timescale)
    var pixelBuffer: CVPixelBuffer?
    let pixelStatus = CVPixelBufferCreate(
        kCFAllocatorDefault,
        width,
        height,
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

func makeTestAudioSample(
    value: Int64,
    timescale: CMTimeScale = 48_000,
    frameCount: Int = 4_800,
    kind: ScreenCaptureSampleKind
) throws -> ScreenCaptureSample {
    precondition(kind != .screen)
    let bytesPerFrame = 2 * MemoryLayout<Float>.size
    var description = AudioStreamBasicDescription(
        mSampleRate: 48_000,
        mFormatID: kAudioFormatLinearPCM,
        mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
        mBytesPerPacket: UInt32(bytesPerFrame),
        mFramesPerPacket: 1,
        mBytesPerFrame: UInt32(bytesPerFrame),
        mChannelsPerFrame: 2,
        mBitsPerChannel: 32,
        mReserved: 0
    )
    var formatDescription: CMAudioFormatDescription?
    let formatStatus = CMAudioFormatDescriptionCreate(
        allocator: kCFAllocatorDefault,
        asbd: &description,
        layoutSize: 0,
        layout: nil,
        magicCookieSize: 0,
        magicCookie: nil,
        extensions: nil,
        formatDescriptionOut: &formatDescription
    )
    guard formatStatus == noErr, let formatDescription else {
        throw TestSampleError.creationFailed(formatStatus)
    }

    let byteCount = frameCount * bytesPerFrame
    var blockBuffer: CMBlockBuffer?
    let blockStatus = CMBlockBufferCreateWithMemoryBlock(
        allocator: kCFAllocatorDefault,
        memoryBlock: nil,
        blockLength: byteCount,
        blockAllocator: kCFAllocatorDefault,
        customBlockSource: nil,
        offsetToData: 0,
        dataLength: byteCount,
        flags: 0,
        blockBufferOut: &blockBuffer
    )
    guard blockStatus == kCMBlockBufferNoErr, let blockBuffer else {
        throw TestSampleError.creationFailed(blockStatus)
    }
    let fillStatus = CMBlockBufferFillDataBytes(
        with: 0,
        blockBuffer: blockBuffer,
        offsetIntoDestination: 0,
        dataLength: byteCount
    )
    guard fillStatus == kCMBlockBufferNoErr else {
        throw TestSampleError.creationFailed(fillStatus)
    }

    let presentationTime = CMTime(value: value, timescale: timescale)
    var timing = CMSampleTimingInfo(
        duration: CMTime(value: 1, timescale: 48_000),
        presentationTimeStamp: presentationTime,
        decodeTimeStamp: .invalid
    )
    var sampleSize = bytesPerFrame
    var sampleBuffer: CMSampleBuffer?
    let sampleStatus = CMSampleBufferCreateReady(
        allocator: kCFAllocatorDefault,
        dataBuffer: blockBuffer,
        formatDescription: formatDescription,
        sampleCount: frameCount,
        sampleTimingEntryCount: 1,
        sampleTimingArray: &timing,
        sampleSizeEntryCount: 1,
        sampleSizeArray: &sampleSize,
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
