import AVFoundation
import RecordCore

extension AudioActivity {
    /// Samples at most 128 frames on each of eight channels, without retaining
    /// audio. Used on media workers and the explicit no-file input test.
    public func record(buffer: AVAudioPCMBuffer) {
        let step = max(1, (Int(buffer.frameLength) + 127) / 128)
        var peak: Double = 0
        for channel in 0..<min(8, Int(buffer.format.channelCount)) {
            for frame in stride(from: 0, to: Int(buffer.frameLength), by: step) {
                let index = frame * buffer.stride
                let sample: Double
                if let samples = buffer.floatChannelData {
                    sample = Double(samples[channel][index])
                } else if let samples = buffer.int16ChannelData {
                    sample = Double(samples[channel][index]) / 32_768
                } else if let samples = buffer.int32ChannelData {
                    sample = Double(samples[channel][index]) / 2_147_483_648
                } else {
                    return
                }
                if sample.isFinite { peak = max(peak, abs(sample)) }
            }
        }
        record(peak: peak)
    }
}
