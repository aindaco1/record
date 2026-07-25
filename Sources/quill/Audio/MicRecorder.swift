import AVFoundation
import Foundation

/// Records the default input device to a file via AVAudioEngine, encoding AAC
/// in the mic's native format. Buffers stream straight to disk — nothing is
/// held in memory, so session length is unbounded.
final class MicRecorder {
    enum RecorderError: Error, CustomStringConvertible {
        case engineStartFailed(Error)
        case fileCreationFailed(Error)
        case formatUnsupported(AVAudioFormat)

        var description: String {
            switch self {
            case .engineStartFailed(let e): return "mic engine start failed: \(e)"
            case .fileCreationFailed(let e): return "mic file creation failed: \(e)"
            case .formatUnsupported(let f): return "can't downmix mic format \(f)"
            }
        }
    }

    private let engine = AVAudioEngine()
    private var file: AVAudioFile?
    private(set) var isRecording = false
    /// Wall-clock time of the first captured buffer — the track's true start,
    /// used to offset-align the two tracks' transcript timestamps.
    private(set) var firstBufferAt: Date?

    /// Start capturing the mic, encoding AAC into `url` (use a .caf extension
    /// — CAF needs no finalization pass, so a crash loses nothing written).
    func start(writingTo url: URL) throws {
        guard !isRecording else { return }

        let input = engine.inputNode
        // Apple's voice-processing stack (echo cancellation): subtracts what
        // the speakers are playing from what the mic hears, so the system
        // track doesn't bleed into the mic track when recording without
        // headphones. Enable before reading the format — it changes it.
        if Config.micVoiceProcessing() {
            do {
                try input.setVoiceProcessingEnabled(true)
            } catch {
                FileHandle.standardError.write(Data(
                    "warning: mic voice processing unavailable (\(error)) — recording raw mic\n".utf8
                ))
            }
        }
        let inputFormat = input.outputFormat(forBus: 0)

        // Always record mono. Some inputs present exotic layouts (a 9-channel
        // device silently produced a zero-byte AAC file), and speech models
        // want one channel anyway — so downmix rather than trusting the
        // device's format.
        guard let recordFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: inputFormat.sampleRate,
            channels: 1,
            interleaved: false
        ), let converter = AVAudioConverter(from: inputFormat, to: recordFormat) else {
            throw RecorderError.formatUnsupported(inputFormat)
        }

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: recordFormat.sampleRate,
            AVNumberOfChannelsKey: 1,
        ]
        do {
            file = try AVAudioFile(
                forWriting: url,
                settings: settings,
                commonFormat: recordFormat.commonFormat,
                interleaved: recordFormat.isInterleaved
            )
        } catch {
            throw RecorderError.fileCreationFailed(error)
        }

        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self, let file = self.file else { return }
            if self.firstBufferAt == nil { self.firstBufferAt = Date() }
            guard let mono = AVAudioPCMBuffer(
                pcmFormat: recordFormat,
                frameCapacity: buffer.frameCapacity
            ) else { return }
            do {
                // Same sample rate on both sides, so the one-shot convert
                // applies — no input-block bookkeeping.
                try converter.convert(to: mono, from: buffer)
                try file.write(from: mono)
            } catch {
                FileHandle.standardError.write(Data("mic track write failed: \(error)\n".utf8))
            }
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            file = nil
            throw RecorderError.engineStartFailed(error)
        }

        isRecording = true
    }

    /// Stop capturing and finalize the file. Idempotent.
    func stop() {
        guard isRecording else { return }
        isRecording = false
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        file = nil
    }
}
