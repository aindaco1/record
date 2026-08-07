import AVFoundation
import CoreAudio
import Foundation
import RecordCore

/// Records the default input device to one crash-resilient AAC/CAF track.
/// Capture callbacks only copy into a bounded handoff; conversion, encoding,
/// and filesystem work happen on the writer queue.
///
/// Apple's VoiceProcessingIO echo canceller is enabled by default. Route and
/// engine-configuration changes are debounced and restart the graph without
/// replacing the output file; silence padding preserves the track timeline.
final class MicRecorder: @unchecked Sendable {
    private enum RouteChangeSource: Equatable {
        case defaultInput
        case engineConfiguration
        case livenessFailure
    }

    enum RecorderError: Error, CustomStringConvertible {
        case engineStartFailed(Error)
        case fileCreationFailed(Error)
        case formatUnsupported(String)

        static func unsupportedFormat(_ format: AVAudioFormat) -> Self {
            .formatUnsupported(String(describing: format))
        }

        var description: String {
            switch self {
            case .engineStartFailed(let error): return "mic engine start failed: \(error)"
            case .fileCreationFailed(let error): return "mic file creation failed: \(error)"
            case .formatUnsupported(let format): return "can't downmix mic format \(format)"
            }
        }
    }

    private var engine = AVAudioEngine()
    private var tapInstalled = false
    private var writer: AudioFileWritePump?
    private var engineObserver: NSObjectProtocol?
    private var defaultInputObserver: DefaultInputDeviceObserver?
    private var scheduledRecovery: DispatchWorkItem?
    private var scheduledLivenessCheck: DispatchWorkItem?
    private var routeRecovery = MicrophoneRouteRecoveryStateMachine()
    private var restartLiveness = MicrophoneRestartLivenessGuard()
    private var preferRawInputUntilStop = false
    private var usingVoiceProcessing = false
    private let startedAt: Date
    private let onHealth: @Sendable (CaptureHealthEvent) -> Void

    private(set) var isRecording = false
    var firstBufferAt: Date? { writer?.snapshot().firstBufferAt }

    init(
        startedAt: Date = Date(),
        onHealth: @escaping @Sendable (CaptureHealthEvent) -> Void = { _ in }
    ) {
        self.startedAt = startedAt
        self.onHealth = onHealth
    }

    func start(writingTo url: URL) throws {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !isRecording else { return }

        let initialInput = engine.inputNode.outputFormat(forBus: 0)
        guard let fileFormat = Self.monoFormat(sampleRate: initialInput.sampleRate) else {
            throw RecorderError.unsupportedFormat(initialInput)
        }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: fileFormat.sampleRate,
            AVNumberOfChannelsKey: 1,
        ]
        let file: AVAudioFile
        do {
            file = try AVAudioFile(
                forWriting: url,
                settings: settings,
                commonFormat: fileFormat.commonFormat,
                interleaved: fileFormat.isInterleaved
            )
        } catch {
            throw RecorderError.fileCreationFailed(error)
        }
        writer = AudioFileWritePump(file: file) { [weak self] event in
            DispatchQueue.main.async { self?.report(event) }
        }

        do {
            try attachEngine(voiceProcessing: Config.micVoiceProcessing())
        } catch {
            writer?.finish()
            writer = nil
            throw error
        }

        isRecording = true
        _ = routeRecovery.handle(.start)
        installDefaultInputObserver()
        beginEngineLivenessCheck(atMilliseconds: elapsedMilliseconds())
    }

    func stop() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard isRecording else { return }
        isRecording = false
        execute(routeRecovery.handle(.stop))
        scheduledRecovery?.cancel()
        scheduledRecovery = nil
        scheduledLivenessCheck?.cancel()
        scheduledLivenessCheck = nil
        restartLiveness.cancel()
        defaultInputObserver = nil
        tearDownEngine()

        let snapshot = writer?.snapshot()
        writer?.finish()
        if snapshot?.receivedBuffers == 0 {
            report(
                .init(
                    track: .microphone,
                    code: .missingCallbacks,
                    severity: .failed,
                    occurredAtMilliseconds: elapsedMilliseconds()
                )
            )
        }
        writer = nil
    }

    // MARK: Capture graph

    private func attachEngine(voiceProcessing requestedVoiceProcessing: Bool) throws {
        guard let writer else {
            throw RecorderError.fileCreationFailed(
                NSError(domain: "Record.MicRecorder", code: 1)
            )
        }

        let newEngine = AVAudioEngine()
        let input = newEngine.inputNode
        var voiceProcessing = requestedVoiceProcessing
        if voiceProcessing {
            do {
                try input.setVoiceProcessingEnabled(true)
                input.voiceProcessingOtherAudioDuckingConfiguration =
                    .init(enableAdvancedDucking: false, duckingLevel: .min)
            } catch {
                FileHandle.standardError.write(
                    Data("warning: mic voice processing unavailable; recording raw mic\n".utf8)
                )
                voiceProcessing = false
            }
        }

        let inputFormat = input.outputFormat(forBus: 0)
        guard let monoFormat = Self.monoFormat(sampleRate: inputFormat.sampleRate) else {
            throw RecorderError.unsupportedFormat(inputFormat)
        }

        let livenessProbe =
            voiceProcessing
            ? VoiceProcessingLivenessProbe(requiredFrames: Int(monoFormat.sampleRate))
            : nil
        if voiceProcessing {
            // VoiceProcessingIO is duplex. An empty render path activates its
            // echo reference without monitoring microphone audio to speakers.
            newEngine.connect(newEngine.mainMixerNode, to: newEngine.outputNode, format: monoFormat)
            input.installTap(onBus: 0, bufferSize: 4_096, format: monoFormat) {
                [weak self, writer, livenessProbe] buffer, _ in
                writer.enqueueCopy(of: buffer)
                if livenessProbe?.consume(buffer) == true {
                    Task { @MainActor [weak self] in
                        self?.fallBackToRawAfterDigitalSilence()
                    }
                }
            }
        } else {
            input.installTap(onBus: 0, bufferSize: 4_096, format: inputFormat) {
                [writer] buffer, _ in
                writer.enqueueCopy(of: buffer)
            }
        }

        newEngine.prepare()
        do {
            try newEngine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw RecorderError.engineStartFailed(error)
        }

        engine = newEngine
        tapInstalled = true
        usingVoiceProcessing = voiceProcessing
        installEngineObserver(for: newEngine)
        let report =
            "mic: voiceProcessing=\(input.isVoiceProcessingEnabled) "
            + "input=\(inputFormat) tap=\(voiceProcessing ? monoFormat : inputFormat)\n"
        FileHandle.standardError.write(Data(report.utf8))
    }

    private func tearDownEngine() {
        if let engineObserver {
            NotificationCenter.default.removeObserver(engineObserver)
            self.engineObserver = nil
        }
        engine.stop()
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        usingVoiceProcessing = false
    }

    private static func monoFormat(sampleRate: Double) -> AVAudioFormat? {
        guard sampleRate > 0 else { return nil }
        return AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        )
    }

    // MARK: Route recovery

    private func installDefaultInputObserver() {
        defaultInputObserver = try? DefaultInputDeviceObserver { [weak self] in
            self?.routeDidChange(.defaultInput)
        }
    }

    private func installEngineObserver(for engine: AVAudioEngine) {
        engineObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            self?.routeDidChange(.engineConfiguration)
        }
    }

    private func routeDidChange(_ source: RouteChangeSource) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard isRecording else { return }
        let changedAt = elapsedMilliseconds()
        if source == .engineConfiguration,
            restartLiveness.shouldDeferEngineConfigurationChange(
                atMilliseconds: changedAt
            )
        {
            return
        }
        scheduledLivenessCheck?.cancel()
        scheduledLivenessCheck = nil
        restartLiveness.cancel()
        execute(
            routeRecovery.handle(
                .routeChanged(atMilliseconds: changedAt)
            )
        )
    }

    private func execute(_ effects: [MicrophoneRouteRecoveryStateMachine.Effect]) {
        for effect in effects {
            switch effect {
            case .scheduleRestart(let milliseconds):
                schedule(afterMilliseconds: milliseconds) { [weak self] in
                    guard let self else { return }
                    self.execute(
                        self.routeRecovery.handle(
                            .restartDelayElapsed(atMilliseconds: self.elapsedMilliseconds())
                        )
                    )
                }
            case .restartCapture:
                restartForRouteChange()
            case .scheduleRetry(let milliseconds):
                schedule(afterMilliseconds: milliseconds) { [weak self] in
                    guard let self else { return }
                    self.execute(
                        self.routeRecovery.handle(
                            .retryDelayElapsed(atMilliseconds: self.elapsedMilliseconds())
                        )
                    )
                }
            case .record(let event):
                report(event)
            }
        }
    }

    private func schedule(afterMilliseconds milliseconds: Int, action: @escaping () -> Void) {
        scheduledRecovery?.cancel()
        let item = DispatchWorkItem(block: action)
        scheduledRecovery = item
        DispatchQueue.main.asyncAfter(
            deadline: .now() + .milliseconds(milliseconds),
            execute: item
        )
    }

    private func restartForRouteChange() {
        guard isRecording else { return }
        guard case .restarting = routeRecovery.state else { return }
        scheduledLivenessCheck?.cancel()
        scheduledLivenessCheck = nil
        restartLiveness.cancel()
        tearDownEngine()
        padMicrophoneGapThroughNow()
        do {
            try attachEngine(
                voiceProcessing: Config.micVoiceProcessing() && !preferRawInputUntilStop
            )
            let recoveredAt = elapsedMilliseconds()
            execute(routeRecovery.handle(.restartSucceeded(atMilliseconds: recoveredAt)))
            beginEngineLivenessCheck(atMilliseconds: recoveredAt)
        } catch {
            let failedAt = elapsedMilliseconds()
            FileHandle.standardError.write(Data("mic route restart failed: \(error)\n".utf8))
            execute(routeRecovery.handle(.restartFailed(atMilliseconds: failedAt)))
        }
    }

    private func beginEngineLivenessCheck(atMilliseconds: Int) {
        restartLiveness.begin(
            atMilliseconds: atMilliseconds,
            voiceProcessingEnabled: usingVoiceProcessing
        )
        scheduledLivenessCheck?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.evaluateRestartLiveness()
        }
        scheduledLivenessCheck = item
        DispatchQueue.main.asyncAfter(
            deadline: .now()
                + .milliseconds(MicrophoneRestartLivenessGuard.stabilizationMilliseconds),
            execute: item
        )
    }

    private func evaluateRestartLiveness() {
        dispatchPrecondition(condition: .onQueue(.main))
        scheduledLivenessCheck = nil
        guard isRecording else { return }
        let evaluatedAt = elapsedMilliseconds()
        let lastCallbackAt = writer?.snapshot().lastBufferAt.map {
            elapsedMilliseconds(at: $0)
        }
        guard
            let decision = restartLiveness.evaluate(
                atMilliseconds: evaluatedAt,
                lastCallbackAtMilliseconds: lastCallbackAt,
                captureIsRunning: engine.isRunning
            )
        else { return }

        switch decision {
        case .healthy:
            return
        case .fallBackToRaw:
            fallBackToRawAfterRouteInstability()
        case .retryCapture:
            report(
                .init(
                    track: .microphone,
                    code: .routeRecoveryFailed,
                    severity: .degraded,
                    occurredAtMilliseconds: evaluatedAt
                )
            )
            routeDidChange(.livenessFailure)
        }
    }

    private func fallBackToRawAfterRouteInstability() {
        guard isRecording else { return }
        preferRawInputUntilStop = true
        report(
            .init(
                track: .microphone,
                code: .voiceProcessingFallback,
                severity: .degraded,
                occurredAtMilliseconds: elapsedMilliseconds()
            )
        )
        tearDownEngine()
        padMicrophoneGapThroughNow()
        do {
            try attachEngine(voiceProcessing: false)
            beginEngineLivenessCheck(atMilliseconds: elapsedMilliseconds())
        } catch {
            FileHandle.standardError.write(Data("mic raw route fallback failed: \(error)\n".utf8))
            routeDidChange(.livenessFailure)
        }
    }

    private func padMicrophoneGapThroughNow() {
        guard let writer, let lastBufferAt = writer.snapshot().lastBufferAt else { return }
        let now = Date()
        let duration = max(0, Int(now.timeIntervalSince(lastBufferAt) * 1_000))
        writer.enqueueSilence(durationMilliseconds: duration, capturedAt: now)
    }

    private func fallBackToRawAfterDigitalSilence() {
        guard isRecording, usingVoiceProcessing else { return }
        preferRawInputUntilStop = true
        scheduledLivenessCheck?.cancel()
        scheduledLivenessCheck = nil
        restartLiveness.cancel()
        let fallbackStartedAt = elapsedMilliseconds()
        report(
            .init(
                track: .microphone,
                code: .digitalSilence,
                severity: .degraded,
                occurredAtMilliseconds: fallbackStartedAt,
                durationMilliseconds: 1_000
            )
        )
        tearDownEngine()
        padMicrophoneGapThroughNow()
        do {
            try attachEngine(voiceProcessing: false)
            beginEngineLivenessCheck(atMilliseconds: elapsedMilliseconds())
        } catch {
            FileHandle.standardError.write(Data("mic raw fallback failed: \(error)\n".utf8))
            report(
                .init(
                    track: .microphone,
                    code: .routeRecoveryFailed,
                    severity: .failed,
                    occurredAtMilliseconds: elapsedMilliseconds()
                )
            )
        }
    }

    // MARK: Health

    private func report(_ event: AudioFileWritePump.Event) {
        switch event {
        case .queuePressure:
            report(
                .init(
                    track: .microphone,
                    code: .queuePressure,
                    severity: .degraded,
                    occurredAtMilliseconds: elapsedMilliseconds()
                )
            )
        case .writeFailed:
            report(
                .init(
                    track: .microphone,
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
            Data("capture health: microphone \(event.code.rawValue)\n".utf8)
        )
    }

    private func elapsedMilliseconds(at date: Date = Date()) -> Int {
        max(0, Int(date.timeIntervalSince(startedAt) * 1_000))
    }
}

/// Core Audio reports a default-device swap independently of AVAudioEngine's
/// graph notification. Listening to both covers unplug, Bluetooth handoff,
/// and Control Center input changes; the state machine coalesces duplicates.
private final class DefaultInputDeviceObserver {
    private var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultInputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    private let listener: AudioObjectPropertyListenerBlock

    init(handler: @escaping @Sendable () -> Void) throws {
        listener = { _, _ in handler() }
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            .main,
            listener
        )
        guard status == noErr else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    deinit {
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            .main,
            listener
        )
    }
}

private final class VoiceProcessingLivenessProbe: @unchecked Sendable {
    private let requiredFrames: Int
    private let lock = NSLock()
    private var frames = 0
    private var peak: Float = 0
    private var settled = false

    init(requiredFrames: Int) {
        self.requiredFrames = max(1, requiredFrames)
    }

    /// Returns true exactly once after one second of callback data contains
    /// only digital zeros.
    func consume(_ buffer: AVAudioPCMBuffer) -> Bool {
        lock.withLock {
            guard !settled else { return false }
            let frameCount = Int(buffer.frameLength)
            if let channel = buffer.floatChannelData?[0] {
                for index in 0..<frameCount {
                    peak = max(peak, abs(channel[index]))
                }
            }
            frames += frameCount
            guard frames >= requiredFrames else { return false }
            settled = true
            return peak == 0
        }
    }
}
