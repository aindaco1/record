import AVFoundation
import CoreAudio
import Foundation
import RecordCore

/// Records all system audio output to a file via a Core Audio process tap
/// (macOS 14.2+). No virtual device, no kernel extension — the tap mixes every
/// process's output to stereo and hands us buffers through a private aggregate
/// device. First use triggers the one-time "System Audio Recording" TCC prompt
/// and lights the purple recording indicator while active.
final class SystemAudioRecorder: @unchecked Sendable {
    enum RecorderError: Error, CustomStringConvertible {
        case tapCreationFailed(OSStatus)
        case tapFormatUnreadable(OSStatus)
        case aggregateCreationFailed(OSStatus)
        case ioProcCreationFailed(OSStatus)
        case deviceStartFailed(OSStatus)
        case fileCreationFailed(Error)

        var description: String {
            switch self {
            case .tapCreationFailed(let s):
                return
                    "process tap creation failed (OSStatus \(s)) — check System Settings → Privacy & Security → Screen & System Audio Recording"
            case .tapFormatUnreadable(let s):
                return "couldn't read tap stream format (OSStatus \(s))"
            case .aggregateCreationFailed(let s):
                return "aggregate device creation failed (OSStatus \(s))"
            case .ioProcCreationFailed(let s): return "IO proc creation failed (OSStatus \(s))"
            case .deviceStartFailed(let s): return "device start failed (OSStatus \(s))"
            case .fileCreationFailed(let e): return "output file creation failed: \(e)"
            }
        }
    }

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private var writer: AudioFileWritePump?
    private var preparedTap: PreparedSystemAudioTap?
    private let queue = DispatchQueue(label: "com.aindaco.record.system-tap")
    private let startedAt: Date
    private let onHealth: @Sendable (CaptureHealthEvent) -> Void
    private(set) var isRecording = false
    /// Wall-clock time of the first captured buffer — the track's true start,
    /// used to offset-align the two tracks' transcript timestamps.
    var firstBufferAt: Date? { writer?.snapshot().firstBufferAt }

    init(
        startedAt: Date = Date(),
        preparedTap: PreparedSystemAudioTap? = nil,
        onHealth: @escaping @Sendable (CaptureHealthEvent) -> Void = { _ in }
    ) {
        self.startedAt = startedAt
        self.preparedTap = preparedTap
        self.onHealth = onHealth
    }

    /// Start capturing system audio, encoding AAC into `url` (use a .caf
    /// extension — CAF needs no finalization pass, so a crash mid-meeting
    /// loses nothing already written).
    func start(writingTo url: URL) throws {
        guard !isRecording else { return }

        let tap: PreparedSystemAudioTap
        do {
            tap = try preparedTap ?? PreparedSystemAudioTap.create(name: "Record system tap")
        } catch let error as PreparedSystemAudioTap.CreationError {
            throw RecorderError.tapCreationFailed(error.status)
        }
        preparedTap = nil
        guard let tapHandle = tap.consume() else {
            throw RecorderError.tapCreationFailed(kAudioHardwareUnspecifiedError)
        }
        tapID = tapHandle.id

        do {
            let format = try tapStreamFormat()
            try createAggregateDevice(tapUUID: tapHandle.uuid)
            let file = try makeFile(url: url, format: format)
            writer = AudioFileWritePump(file: file) { [weak self] event in
                self?.report(event)
            }
            try installIOProc(format: format)
        } catch {
            cleanup()
            throw error
        }

        isRecording = true
    }

    /// Stop capturing and finalize the file. Idempotent.
    func stop() {
        guard isRecording else { return }
        isRecording = false
        if let procID, aggregateID != kAudioObjectUnknown {
            AudioDeviceStop(aggregateID, procID)
        }
        let snapshot = writer?.snapshot()
        writer?.finish()
        if snapshot?.receivedBuffers == 0 {
            report(
                .init(
                    track: .systemAudio,
                    code: .missingCallbacks,
                    severity: .failed,
                    occurredAtMilliseconds: elapsedMilliseconds()
                )
            )
        }
        cleanup()
    }

    // MARK: -

    private func tapStreamFormat() throws -> AVAudioFormat {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let status = AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &asbd)
        guard status == noErr, let format = AVAudioFormat(streamDescription: &asbd) else {
            throw RecorderError.tapFormatUnreadable(status)
        }
        return format
    }

    private func createAggregateDevice(tapUUID: UUID) throws {
        let desc: [String: Any] = [
            kAudioAggregateDeviceNameKey: "record-tap",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [] as [[String: Any]],
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapUIDKey: tapUUID.uuidString,
                    kAudioSubTapDriftCompensationKey: true,
                ]
            ],
        ]
        var newAggregateID = AudioObjectID(kAudioObjectUnknown)
        let status = AudioHardwareCreateAggregateDevice(desc as CFDictionary, &newAggregateID)
        guard status == noErr else { throw RecorderError.aggregateCreationFailed(status) }
        aggregateID = newAggregateID
    }

    private func makeFile(url: URL, format: AVAudioFormat) throws -> AVAudioFile {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
        ]
        do {
            return try AVAudioFile(
                forWriting: url,
                settings: settings,
                commonFormat: format.commonFormat,
                interleaved: format.isInterleaved
            )
        } catch {
            throw RecorderError.fileCreationFailed(error)
        }
    }

    private func installIOProc(format: AVAudioFormat) throws {
        guard let writer else {
            throw RecorderError.fileCreationFailed(
                NSError(domain: "Record.SystemAudioRecorder", code: 1)
            )
        }
        var status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue) {
            _, inInputData, _, _, _ in
            guard
                let buffer = AVAudioPCMBuffer(
                    pcmFormat: format,
                    bufferListNoCopy: inInputData,
                    deallocator: nil
                )
            else { return }
            writer.enqueueCopy(of: buffer)
        }
        guard status == noErr, let procID else { throw RecorderError.ioProcCreationFailed(status) }

        status = AudioDeviceStart(aggregateID, procID)
        guard status == noErr else { throw RecorderError.deviceStartFailed(status) }
    }

    private func cleanup() {
        if let procID, aggregateID != kAudioObjectUnknown {
            AudioDeviceDestroyIOProcID(aggregateID, procID)
        }
        procID = nil
        if aggregateID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
        writer?.finish()
        writer = nil
    }

    private func report(_ event: AudioFileWritePump.Event) {
        switch event {
        case .queuePressure:
            report(
                .init(
                    track: .systemAudio,
                    code: .queuePressure,
                    severity: .degraded,
                    occurredAtMilliseconds: elapsedMilliseconds()
                )
            )
        case .writeFailed:
            report(
                .init(
                    track: .systemAudio,
                    code: .writeFailed,
                    severity: .failed,
                    occurredAtMilliseconds: elapsedMilliseconds()
                )
            )
        }
    }

    private func report(_ event: CaptureHealthEvent) {
        onHealth(event)
        FileHandle.standardError.write(
            Data("capture health: system_audio \(event.code.rawValue)\n".utf8)
        )
    }

    private func elapsedMilliseconds(at date: Date = Date()) -> Int {
        max(0, Int(date.timeIntervalSince(startedAt) * 1_000))
    }
}
