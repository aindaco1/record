import AVFoundation
import RecordCapture
import RecordCore
import XCTest

final class AudioBufferActivityTests: XCTestCase {
    func testStereoActivityReadsBothInterleavedAndPlanarChannels() throws {
        for interleaved in [false, true] {
            let format = try XCTUnwrap(
                AVAudioFormat(
                    commonFormat: .pcmFormatFloat32, sampleRate: 48_000,
                    channels: 2, interleaved: interleaved))
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 256))
            buffer.frameLength = 256
            let samples = try XCTUnwrap(buffer.floatChannelData)
            for channel in 0..<2 {
                for frame in 0..<256 { samples[channel][frame * buffer.stride] = 0 }
            }
            samples[1][128 * buffer.stride] = 1
            let activity = AudioActivity()
            activity.record(buffer: buffer)
            XCTAssertEqual(activity.level(), 1, accuracy: 0.001)
        }
    }
}
