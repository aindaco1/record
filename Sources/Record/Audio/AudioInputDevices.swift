import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation
import RecordCore
import RecordCapture

/// Hardware discovery and routing stay outside the deterministic capture policy.
enum AudioInputDevices {
    struct Device: Equatable, Sendable { let id: AudioDeviceID; let uid: String; let name: String }
    enum InputError: Error { case unavailable, routeFailed(OSStatus) }

    static func available() -> [Device] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard
            AudioObjectGetPropertyDataSize(
                AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr
        else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr
        else { return [] }
        return ids.compactMap { id in
            var streams = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreams,
                mScope: kAudioDevicePropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
            var size: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &streams, 0, nil, &size) == noErr, size > 0,
                let uid = string(id, kAudioDevicePropertyDeviceUID),
                isUserSelectable(uid: uid),
                let name = string(id, kAudioObjectPropertyName)
            else { return nil }
            return Device(id: id, uid: uid, name: name)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func isUserSelectable(
        uid: String, processID: Int32 = ProcessInfo.processInfo.processIdentifier
    ) -> Bool {
        // AVAudioEngine exposes its own temporary default-route aggregate to
        // this process. It disappears with the engine and is not a saved input.
        !uid.hasPrefix("CADefaultDeviceAggregate-\(processID)-")
    }

    private static func string(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector)
        -> String?
    {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>? = nil
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else {
            return nil
        }
        return value?.takeRetainedValue() as String?
    }

    static func select(_ uid: String?, on input: AVAudioInputNode) throws {
        guard let uid else { return }
        guard var device = available().first(where: { $0.uid == uid })?.id,
            let unit = input.audioUnit
        else { throw InputError.unavailable }
        var current: AudioDeviceID = 0
        var currentSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        if AudioUnitGetProperty(
            unit, kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global, 0, &current, &currentSize) == noErr, current == device
        {
            return
        }
        let result = AudioUnitSetProperty(
            unit, kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global, 0, &device, UInt32(MemoryLayout<AudioDeviceID>.size))
        guard result == noErr else { throw InputError.routeFailed(result) }
    }
}

@MainActor
final class AudioInputDeviceMonitor {
    private var listener: AudioObjectPropertyListenerBlock?
    private var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    func start(onChange: @escaping @MainActor @Sendable () -> Void) {
        guard listener == nil else { return }
        let listener: AudioObjectPropertyListenerBlock = { _, _ in
            MainActor.assumeIsolated { onChange() }
        }
        if AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address,
            .main, listener) == noErr
        {
            self.listener = listener
        }
    }
    func stop() {
        if let listener {
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &address, .main, listener)
        }
        listener = nil
    }
}

@MainActor
final class AudioInputTest {
    private var engine: AVAudioEngine?
    private var configurationObserver: NSObjectProtocol?
    private var restarts = 0
    let activity = AudioActivity()
    func start(uid: String?) async throws {
        stop()
        guard await AVCaptureDevice.requestAccess(for: .audio) else {
            throw AudioInputDevices.InputError.unavailable
        }
        try Task.checkCancellation()
        let engine = AVAudioEngine()
        let input = engine.inputNode
        try AudioInputDevices.select(uid, on: input)
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw AudioInputDevices.InputError.unavailable
        }
        input.installTap(
            onBus: 0, bufferSize: 1_024, format: format, block: Self.tap(activity: activity))
        do { try engine.start(); self.engine = engine } catch {
            input.removeTap(onBus: 0); throw error
        }
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.restartAfterRouteSettles() }
        }
    }
    private func restartAfterRouteSettles() {
        guard let engine, !engine.isRunning, restarts < 2 else { return }
        restarts += 1
        let input = engine.inputNode
        input.removeTap(onBus: 0)
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { stop(); return }
        input.installTap(
            onBus: 0, bufferSize: 1_024, format: format, block: Self.tap(activity: activity))
        do { try engine.start() } catch { stop() }
    }
    nonisolated static func tap(activity: AudioActivity) -> AVAudioNodeTapBlock {
        { @Sendable [activity] buffer, _ in
            activity.record(buffer: buffer)
        }
    }
    func stop() {
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
        }
        configurationObserver = nil
        if let engine { engine.stop(); engine.inputNode.removeTap(onBus: 0) }
        engine = nil
        restarts = 0
        activity.reset()
    }
}
