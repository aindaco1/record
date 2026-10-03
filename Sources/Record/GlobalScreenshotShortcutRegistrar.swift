import Carbon
import Foundation
import RecordCore

struct GlobalScreenshotShortcutFailure: Equatable, Sendable {
    let kind: ScreenshotCaptureKind
    let status: OSStatus
}

enum CarbonScreenshotShortcutPlan {
    static func modifiers(_ modifiers: ScreenshotShortcutModifiers) -> UInt32 {
        var value: UInt32 = 0
        if modifiers.contains(.command) { value |= UInt32(cmdKey) }
        if modifiers.contains(.shift) { value |= UInt32(shiftKey) }
        if modifiers.contains(.option) { value |= UInt32(optionKey) }
        if modifiers.contains(.control) { value |= UInt32(controlKey) }
        return value
    }

    static func identifier(for kind: ScreenshotCaptureKind) -> UInt32 {
        switch kind {
        case .display: 1
        case .windowOrApplication: 2
        case .area: 3
        }
    }

    static func kind(for identifier: UInt32) -> ScreenshotCaptureKind? {
        switch identifier {
        case 1: .display
        case 2: .windowOrApplication
        case 3: .area
        default: nil
        }
    }
}

/// Registers ordinary Carbon global hot keys. This does not use event taps and
/// therefore does not request Accessibility permission. Registration failures
/// are surfaced per shortcut, while the remaining shortcuts stay active.
@MainActor
final class GlobalScreenshotShortcutRegistrar {
    private static let signature: OSType = 0x5245_4344  // "RECD"

    private var handler: EventHandlerRef?
    private var references: [UInt32: EventHotKeyRef] = [:]
    private var pressed = Set<UInt32>()
    var onRecording: ((RecordingShortcutAction) -> Void)?
    var onCapture: ((ScreenshotCaptureKind) -> Void)?

    init() {
        installHandler()
    }

    func apply(_ shortcuts: ScreenshotShortcutSet) -> [GlobalScreenshotShortcutFailure] {
        for id in references.keys.filter({ $0 <= 3 }) {
            if let reference = references.removeValue(forKey: id) {
                UnregisterEventHotKey(reference)
            }
            pressed.remove(id)
        }

        var failures: [GlobalScreenshotShortcutFailure] = []
        for kind in ScreenshotCaptureKind.allCases {
            guard let shortcut = shortcuts[kind] else { continue }
            let status = register(shortcut, id: CarbonScreenshotShortcutPlan.identifier(for: kind))
            if status != noErr { failures.append(.init(kind: kind, status: status)) }
        }
        return failures
    }

    func applyRecording(_ shortcuts: RecordingShortcuts) -> [RecordingShortcutAction] {
        var failures: [RecordingShortcutAction] = []
        for action in RecordingShortcutAction.allCases {
            if let old = references.removeValue(forKey: action.rawValue) {
                UnregisterEventHotKey(old)
            }
            pressed.remove(action.rawValue)
            if let shortcut = shortcuts[action], register(shortcut, id: action.rawValue) != noErr {
                failures.append(action)
            }
        }
        return failures
    }

    private func register(_ shortcut: ScreenshotShortcut, id: UInt32) -> OSStatus {
        var reference: EventHotKeyRef?
        let result = RegisterEventHotKey(
            shortcut.keyCode,
            CarbonScreenshotShortcutPlan.modifiers(shortcut.modifiers),
            EventHotKeyID(signature: Self.signature, id: id), GetApplicationEventTarget(), 0,
            &reference)
        if result == noErr, let reference { references[id] = reference }
        return result
    }

    private func installHandler() {
        var eventTypes = [kEventHotKeyPressed, kEventHotKeyReleased].map {
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32($0))
        }
        let callback: EventHandlerUPP = { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            let owner = Unmanaged<GlobalScreenshotShortcutRegistrar>
                .fromOpaque(context).takeUnretainedValue()
            var identifier = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &identifier
            )
            guard status == noErr,
                identifier.signature == GlobalScreenshotShortcutRegistrar.signature
            else { return OSStatus(eventNotHandledErr) }
            MainActor.assumeIsolated {
                if GetEventKind(event) == UInt32(kEventHotKeyReleased) {
                    owner.pressed.remove(identifier.id)
                } else if owner.pressed.insert(identifier.id).inserted {
                    if let kind = CarbonScreenshotShortcutPlan.kind(for: identifier.id) {
                        owner.onCapture?(kind)
                    } else if let action = RecordingShortcutAction(rawValue: identifier.id) {
                        owner.onRecording?(action)
                    }
                }
            }
            return noErr
        }
        InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            eventTypes.count,
            &eventTypes,
            Unmanaged.passUnretained(self).toOpaque(),
            &handler
        )
    }
}
