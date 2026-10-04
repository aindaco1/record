import AppKit
import RecordCore

@MainActor
final class DictationPreviewController: NSWindowController {
    private let status = NSTextField(wrappingLabelWithString: "")
    private let preview = NSTextView()
    private let copy = NSButton()
    private var loadTask: Task<Void, Never>?
    private var lease: ExportDirectoryLease?
    private(set) var directory: URL?
    private(set) var isProcessing = false
    var onShowSessions: (() -> Void)?

    init() {
        let window = SettingsWindow(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 340),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = L10n.text("Quick Dictation")
        window.contentMinSize = NSSize(width: 480, height: 260)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        preview.isEditable = false
        preview.isSelectable = true
        preview.font = .systemFont(ofSize: 15)
        preview.textContainerInset = NSSize(width: 10, height: 10)
        preview.autoresizingMask = [.width]
        preview.setAccessibilityLabel(L10n.text("Dictation preview"))
        let scroll = NSScrollView()
        scroll.documentView = preview
        scroll.hasVerticalScroller = true
        copy.title = L10n.text("Copy")
        copy.target = self
        copy.action = #selector(copyText)
        copy.isEnabled = false
        let sessions = NSButton(
            title: L10n.text("Sessions…"), target: self, action: #selector(showSessions))
        let stack = NSStackView(views: [status, scroll, NSStackView(views: [copy, sessions])])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = window.contentView!
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            status.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
    }
    @available(*, unavailable) required init?(coder: NSCoder) { nil }

    func begin(directory: URL, retaining lease: ExportDirectoryLease?) {
        loadTask?.cancel()
        self.directory = directory
        self.lease = lease
        isProcessing = true
        preview.string = ""
        copy.isEnabled = false
        status.stringValue = L10n.text(
            "Queued for local transcription. Your audio is saved in Sessions.")
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func update(_ update: TranscriptionCoordinator.Status) {
        guard let directory else { return }
        switch update {
        case .deferred(let session) where session == directory.lastPathComponent:
            isProcessing = false
            status.stringValue = L10n.text(
                "Your audio is safe. Open Sessions to retry transcription.")
        case .progress(let session, let stage, _) where session == directory.lastPathComponent:
            status.stringValue = stage
        case .finished(let finished, let succeeded)
        where PendingTranscription.sameDirectory(finished, directory):
            isProcessing = false
            guard succeeded else {
                status.stringValue = L10n.text(
                    "Your audio is safe. Open Sessions to retry transcription.")
                return
            }
            let retainedLease = lease
            loadTask = Task { [weak self] in
                let text = await Task.detached(priority: .utility) {
                    defer { withExtendedLifetime(retainedLease) {} }
                    return try? TranscriptPreviewReader.read(directory: directory).plainText
                }.value
                guard !Task.isCancelled, let self else { return }
                self.preview.string = text ?? ""
                self.copy.isEnabled = text?.isEmpty == false
                self.status.stringValue =
                    text == nil
                    ? L10n.text("Your audio is safe. Open Sessions to retry transcription.")
                    : (text?.isEmpty == true
                        ? L10n.text("No speech was recognized. Your audio is saved in Sessions.")
                        : L10n.text(
                            "Review your text, then copy it. Audio and transcripts stay in Sessions."
                        ))
            }
        default: break
        }
    }

    @objc private func copyText() {
        guard copy.isEnabled, !preview.string.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(preview.string, forType: .string)
        status.stringValue = L10n.text("Copied. Audio and transcripts stay in Sessions.")
    }
    @objc private func showSessions() { onShowSessions?() }
}
