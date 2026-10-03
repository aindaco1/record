import AppKit
import RecordCore

@MainActor
final class ReadyToRecordWindowController: NSWindowController, NSWindowDelegate {
    private let mode = NSSegmentedControl(
        labels: ["Screen Recording", "Audio Only"],
        trackingMode: .selectOne, target: nil, action: nil)
    private let checklist = NSTextField(wrappingLabelWithString: "")
    private let startButton = NSButton()
    var onRefresh: ((RecordingMode) -> RecordingReadiness)?
    var onChooseFolder: (() -> Void)?
    var onPermissions: ((RecordingMode) -> Void)?
    var onTestInput: (() -> Void)?
    var onModelSetup: (() -> Void)?
    var onStart: ((RecordingMode) -> Void)?
    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 550, height: 460),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Ready to Record"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        mode.selectedSegment = 0
        mode.target = self
        mode.action = #selector(refresh)
        startButton.target = self
        startButton.action = #selector(start)
        let buttons = NSStackView(views: [
            button("Choose Folder…", #selector(folder)),
            button("Check Permissions…", #selector(permissions)),
        ])
        let optional = NSStackView(views: [
            button("Test Input…", #selector(input)), button("Set Up Model…", #selector(model)),
        ])
        let note = NSTextField(
            wrappingLabelWithString:
                "You can return to this checklist from the Record menu. All recordings and transcripts stay on this Mac."
        )
        let stack = NSStackView(views: [
            mode, checklist, buttons, optional, note,
            NSStackView(views: [startButton, button("Done for Now", #selector(done))]),
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView?.addSubview(stack)
        if let content = window.contentView {
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
                stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
                stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            ])
        }
        window.center()
    }
    @available(*, unavailable) required init?(coder: NSCoder) { nil }
    func show() { refresh(); showWindow(nil); NSApp.activate(ignoringOtherApps: true) }
    func windowDidBecomeKey(_ notification: Notification) { refresh() }
    @objc func refresh() {
        startButton.title =
            mode.selectedSegment == 0 ? "Start Screen Recording" : "Start Audio Recording"
        checklist.stringValue =
            onRefresh?(mode.selectedSegment == 0 ? .screen : .audioOnly).checklist.joined(
                separator: "\n\n") ?? ""
    }
    private func button(_ title: String, _ action: Selector) -> NSButton {
        NSButton(title: title, target: self, action: action)
    }
    @objc private func folder() { onChooseFolder?(); refresh() }
    @objc private func permissions() {
        onPermissions?(mode.selectedSegment == 0 ? .screen : .audioOnly)
    }
    @objc private func input() { onTestInput?() }
    @objc private func model() { onModelSetup?() }
    @objc private func start() {
        close()
        onStart?(mode.selectedSegment == 0 ? .screen : .audioOnly)
    }
    @objc private func done() {
        UserDefaults.standard.set(true, forKey: "recording.checklistDismissed"); close()
    }
}
