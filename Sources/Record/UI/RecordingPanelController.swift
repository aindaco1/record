import AppKit
import RecordCore

/// A second view of the menu's presentation, with no capture state or clock.
@MainActor
final class RecordingPanelController: NSWindowController {
    private let label = NSTextField(wrappingLabelWithString: "")
    private let microphone = NSLevelIndicator()
    private let system = NSLevelIndicator()
    private let pause = NSButton()
    private let stop = NSButton()
    private var wasIdle = true
    var onStop: (() -> Void)?
    var onPauseResume: (() -> Void)?

    init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 175),
            styleMask: [.titled, .closable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.title = "Record"
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.sharingType = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        super.init(window: panel)
        stop.title = L10n.text("Stop")
        stop.target = self
        stop.action = #selector(stopClicked)
        pause.target = self
        pause.action = #selector(pauseClicked)
        let controls = NSStackView(views: [pause, stop])
        let stack = NSStackView(views: [
            label, meterRow(L10n.text("Microphone"), microphone),
            meterRow(L10n.text("System audio"), system), controls,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView?.addSubview(stack)
        if let content = panel.contentView {
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
                stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
                stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
                stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
            ])
        }
        panel.setFrameAutosaveName("RecordCompactPanel")
    }
    @available(*, unavailable) required init?(coder: NSCoder) { nil }

    func render(_ presentation: RecordingMenuPresentation, enabled: Bool) {
        let idle = presentation == .idle
        defer { wasIdle = idle }
        if idle { microphone.doubleValue = 0; system.doubleValue = 0 }
        guard enabled, !idle else { window?.orderOut(nil); return }
        label.stringValue = presentation.stateTitle
        pause.title = presentation.pauseResumeTitle
        pause.isEnabled = presentation.pauseResumeEnabled
        pause.isHidden = !presentation.pauseResumeVisible
        stop.isEnabled = presentation.toggleEnabled && !presentation.audioOnlyEnabled
        if wasIdle { window?.orderFrontRegardless() }
    }

    func updateAudio(
        _ levels: (microphone: Double, system: Double), configuration: CaptureAudioConfiguration
    ) {
        microphone.doubleValue = configuration.includeMicrophone ? levels.microphone : 0
        system.doubleValue = configuration.includeSystemAudio ? levels.system : 0
        microphone.setAccessibilityValue(
            configuration.includeMicrophone
                ? L10n.format("%ld percent", Int(levels.microphone * 100)) : L10n.text("Off"))
        system.setAccessibilityValue(
            configuration.includeSystemAudio
                ? L10n.format("%ld percent", Int(levels.system * 100)) : L10n.text("Off"))
    }
    private func meterRow(_ title: String, _ meter: NSLevelIndicator) -> NSView {
        meter.minValue = 0
        meter.maxValue = 1
        meter.levelIndicatorStyle = .continuousCapacity
        meter.setAccessibilityLabel(L10n.format("%@ activity", title))
        meter.widthAnchor.constraint(equalToConstant: 220).isActive = true
        let label = NSTextField(labelWithString: title)
        label.widthAnchor.constraint(equalToConstant: 140).isActive = true
        return NSStackView(views: [label, meter])
    }
    @objc private func stopClicked() { onStop?() }
    @objc private func pauseClicked() { onPauseResume?() }
}
