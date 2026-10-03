import AppKit
import RecordCore

@MainActor
final class ModelSetupWindowController: NSWindowController {
    private let label = NSTextField(wrappingLabelWithString: L10n.text("Preparing model download…"))
    private let progress = NSProgressIndicator()
    private let cancel = NSButton(title: L10n.text("Cancel"), target: nil, action: nil)
    var onCancel: (() -> Void)?
    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 450, height: 150),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.title = L10n.text("Set Up Local Transcription")
        window.isReleasedWhenClosed = false
        super.init(window: window)
        progress.minValue = 0
        progress.maxValue = 1
        progress.isIndeterminate = true
        progress.setAccessibilityLabel(L10n.text("Model setup progress"))
        cancel.target = self
        cancel.action = #selector(cancelClicked)
        let stack = NSStackView(views: [label, progress, cancel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView?.addSubview(stack)
        if let content = window.contentView {
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
                stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
                stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
                progress.widthAnchor.constraint(equalTo: stack.widthAnchor),
            ])
        }
        window.center()
    }
    @available(*, unavailable) required init?(coder: NSCoder) { nil }
    func begin() {
        cancel.isEnabled = true
        cancel.title = L10n.text("Cancel")
        update(.downloading(0))
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func update(_ stage: ParakeetModelInstaller.Progress) {
        switch stage {
        case .downloading(let bytes):
            let total = ParakeetModelDownloadDescriptor.v3.byteCount
            progress.isIndeterminate = false
            progress.doubleValue = Double(bytes) / Double(total)
            label.stringValue =
                L10n.format(
                    "Downloading model · %@ of %@",
                    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file),
                    ByteCountFormatter.string(fromByteCount: total, countStyle: .file))
        case .verifying, .extracting, .installing:
            progress.isIndeterminate = true
            progress.startAnimation(nil)
            switch stage {
            case .verifying: label.stringValue = L10n.text("Verifying the download…")
            case .extracting: label.stringValue = L10n.text("Expanding the verified model…")
            default: label.stringValue = L10n.text("Verifying and installing the local model…")
            }
        }
    }
    @objc private func cancelClicked() {
        cancel.isEnabled = false
        cancel.title = L10n.text("Cancelling…")
        onCancel?()
    }
}
