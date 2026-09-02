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
    private var references: [ScreenshotCaptureKind: EventHotKeyRef] = [:]
    var onCapture: ((ScreenshotCaptureKind) -> Void)?

    init() {
        installHandler()
    }

    func apply(_ shortcuts: ScreenshotShortcutSet) -> [GlobalScreenshotShortcutFailure] {
        for reference in references.values {
            UnregisterEventHotKey(reference)
        }
        references.removeAll()

        var failures: [GlobalScreenshotShortcutFailure] = []
        for kind in ScreenshotCaptureKind.allCases {
            guard let shortcut = shortcuts[kind] else { continue }
            var reference: EventHotKeyRef?
            let identifier = EventHotKeyID(
                signature: Self.signature,
                id: CarbonScreenshotShortcutPlan.identifier(for: kind)
            )
            let status = RegisterEventHotKey(
                shortcut.keyCode,
                CarbonScreenshotShortcutPlan.modifiers(shortcut.modifiers),
                identifier,
                GetApplicationEventTarget(),
                0,
                &reference
            )
            if status == noErr, let reference {
                references[kind] = reference
            } else {
                failures.append(.init(kind: kind, status: status))
            }
        }
        return failures
    }

    private func installHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
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
                identifier.signature == GlobalScreenshotShortcutRegistrar.signature,
                let kind = CarbonScreenshotShortcutPlan.kind(for: identifier.id)
            else { return OSStatus(eventNotHandledErr) }
            MainActor.assumeIsolated {
                owner.onCapture?(kind)
            }
            return noErr
        }
        InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handler
        )
    }
}
