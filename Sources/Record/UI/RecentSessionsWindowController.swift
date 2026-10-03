import AppKit
import RecordCore

@MainActor
final class RecentSessionsWindowController: NSWindowController, NSTableViewDataSource,
    NSTableViewDelegate, NSSearchFieldDelegate, NSWindowDelegate
{
    private let search = NSSearchField()
    private let table = NSTableView()
    private let preview = NSTextView()
    private var displayedTranscript: String?
    private let variant = NSSegmentedControl(
        labels: ["Clean transcript", "Raw transcript"],
        trackingMode: .selectOne, target: nil, action: nil)
    private let status = NSTextField(wrappingLabelWithString: "")
    private lazy var revealButton = button("Reveal", #selector(reveal))
    private lazy var copyButton = button("Copy transcript", #selector(copyTranscript))
    private lazy var retryButton = button("Retry unfinished tracks", #selector(retry))
    private lazy var deferButton = button("Transcribe later", #selector(deferWork))
    private lazy var microphoneButton = button("Play microphone", #selector(playMicrophone))
    private lazy var systemButton = button("Play system audio", #selector(playSystemAudio))
    private lazy var videoButton = button("Play video", #selector(playVideo))
    private var sessions: [RecentRecordingLocator.Candidate] = []
    private var filtered: [RecentRecordingLocator.Candidate] = []
    private var lease: ExportDirectoryLease?
    private var refreshTask: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
    private var roots: [URL] = []
    var onRetry: ((URL, ExportDirectoryLease?) -> Void)?
    var onDefer: ((URL) -> Void)?

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 850, height: 650),
            styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered,
            defer: false)
        window.title = "Recent Sessions"
        window.minSize = NSSize(width: 680, height: 500)
        super.init(window: window)
        window.delegate = self
        search.placeholderString = "Filter by title or date (YYYY-MM-DD)"
        search.delegate = self
        search.setAccessibilityLabel("Filter sessions by title or date")
        table.addTableColumn(NSTableColumn(identifier: .init("session")))
        table.headerView = nil
        table.rowHeight = 54
        table.delegate = self
        table.dataSource = self
        table.setAccessibilityLabel("Recent recording sessions")
        let list = NSScrollView()
        list.documentView = table
        list.hasVerticalScroller = true
        list.heightAnchor.constraint(equalToConstant: 230).isActive = true
        preview.isEditable = false
        preview.isSelectable = true
        preview.font = .systemFont(ofSize: 13)
        preview.textContainerInset = NSSize(width: 10, height: 10)
        preview.autoresizingMask = [.width]
        preview.setAccessibilityLabel("Transcript preview")
        let text = NSScrollView()
        text.documentView = preview
        text.hasVerticalScroller = true
        variant.selectedSegment = 0
        variant.target = self
        variant.action = #selector(showSelection)
        let actions = NSStackView(views: [
            revealButton, copyButton, retryButton, deferButton,
        ])
        let playback = NSStackView(views: [
            microphoneButton, systemButton, videoButton, button("Refresh", #selector(refresh)),
        ])
        let stack = NSStackView(views: [search, list, status, playback, variant, text, actions])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView?.addSubview(stack)
        if let content = window.contentView {
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
                stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
                stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
                stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
            ])
        }
        for view in [search, list, status, text] {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        window.center()
    }

    @available(*, unavailable) required init?(coder: NSCoder) { nil }

    func show(roots: [URL], retaining lease: ExportDirectoryLease?) {
        update(roots: roots, retaining: lease)
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func update(roots: [URL], retaining lease: ExportDirectoryLease?) {
        if self.roots != roots {
            previewTask?.cancel()
            preview.string = ""
            displayedTranscript = nil
            sessions = []
            filtered = []
            table.reloadData()
        }
        self.roots = roots
        self.lease = lease
        refresh()
    }

    func windowWillClose(_ notification: Notification) {
        refreshTask?.cancel()
        previewTask?.cancel()
        lease = nil
        sessions = []
        filtered = []
        preview.string = ""
        displayedTranscript = nil
    }

    @objc func refresh() {
        guard window?.isVisible == true || !roots.isEmpty else { return }
        refreshTask?.cancel()
        let roots = roots
        let retainedLease = lease
        refreshTask = Task { [weak self] in
            let result = await Task.detached(priority: .utility) {
                defer { withExtendedLifetime(retainedLease) {} }
                return RecentRecordingLocator.sessions(under: roots)
            }.value
            guard !Task.isCancelled, let self else { return }
            self.sessions = result
            self.filterSessions()
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { filtered.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int)
        -> NSView?
    {
        let session = filtered[row]
        let duration = max(
            0,
            Int(
                (session.manifest.endedAt ?? session.manifest.startedAt)
                    .timeIntervalSince(session.manifest.startedAt)))
        let kind = session.manifest.tracks.contains { $0.kind == .screen } ? "Screen" : "Audio"
        let transcription =
            session.transcription.map {
                $0.state.title + " \($0.completedTracks)/\($0.tracks.count)"
            }
            ?? (session.hasTranscript ? "transcribed" : "no transcript")
        let label = NSTextField(
            wrappingLabelWithString: "\(session.directory.lastPathComponent)\n"
                + "\(session.manifest.startedAt.formatted(date: .numeric, time: .shortened)) · \(duration / 60):"
                + String(format: "%02d", duration % 60)
                + " · \(kind) · \(session.manifest.state.rawValue) · \(transcription)")
        return label
    }
    func tableViewSelectionDidChange(_ notification: Notification) { showSelection() }
    func controlTextDidChange(_ notification: Notification) { filterSessions() }

    private func filterSessions() {
        let selected = selection?.directory
        let query = search.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        filtered = sessions.filter {
            SessionSearch.matches(
                query, title: $0.directory.lastPathComponent, startedAt: $0.manifest.startedAt)
        }
        table.reloadData()
        if let row = filtered.firstIndex(where: { $0.directory == selected })
            ?? (filtered.isEmpty ? nil : 0)
        {
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        showSelection()
    }

    private var selection: RecentRecordingLocator.Candidate? {
        filtered.indices.contains(table.selectedRow) ? filtered[table.selectedRow] : nil
    }

    @objc private func showSelection() {
        previewTask?.cancel()
        preview.string = ""
        displayedTranscript = nil
        copyButton.isEnabled = false
        revealButton.isEnabled = selection != nil
        let mayTranscribe =
            selection.map {
                ($0.manifest.state == .finalized || $0.manifest.state == .interrupted)
                    && $0.manifest.tracks.contains {
                        $0.kind == .microphone || $0.kind == .systemAudio
                    }
                    && ($0.transcription.map { $0.state != .complete } ?? !$0.hasTranscript)
            } ?? false
        retryButton.isEnabled = mayTranscribe
        deferButton.isEnabled = mayTranscribe && selection?.transcription?.state != .deferred
        for (kind, button) in [
            (SessionManifest.TrackKind.microphone, microphoneButton),
            (.systemAudio, systemButton), (.screen, videoButton),
        ] {
            button.isEnabled = selection?.manifest.tracks.contains { $0.kind == kind } == true
        }
        guard let session = selection else {
            status.stringValue =
                sessions.isEmpty
                ? "No sessions in the current save folder or private recovery storage."
                : "No sessions match this filter."
            return
        }
        let raw = variant.selectedSegment == 1
        let retainedLease = lease
        previewTask = Task { [weak self] in
            let result = await Task.detached(priority: .utility) { () -> (String, String?) in
                defer { withExtendedLifetime(retainedLease) {} }
                let checkpoint = try? TranscriptionCheckpoint.read(from: session.directory)
                let state =
                    checkpoint.map {
                        "\($0.state.title) · "
                            + $0.tracks.map {
                                "\($0.source.speaker == "me" ? "Microphone" : "System audio"): \($0.segments != nil ? "complete" : "unfinished")"
                            }.joined(separator: " · ")
                    } ?? (session.hasTranscript ? "Transcript ready" : "Transcription not started")
                let url = session.directory.appendingPathComponent(
                    raw ? "transcript.raw.json" : "transcript.json")
                guard let size = LocalFilePolicy.regularFileSize(at: url),
                    size <= 8 * 1_024 * 1_024,
                    let data = try? Data(contentsOf: url),
                    let transcript = try? JSONDecoder().decode(TranscriptDocument.self, from: data)
                else { return (state, nil) }
                return (state, transcript.rendered(title: session.directory.lastPathComponent))
            }.value
            guard !Task.isCancelled else { return }
            self?.status.stringValue = result.0
            self?.displayedTranscript = result.1
            self?.copyButton.isEnabled = result.1 != nil
            self?.preview.string =
                result.1
                ?? "No preview is available. Use Reveal to inspect the session and its source files."
        }
    }

    func updateProgress(session: String, stage: String) {
        if selection?.directory.lastPathComponent == session { status.stringValue = stage }
    }

    private func button(_ title: String, _ action: Selector) -> NSButton {
        NSButton(title: title, target: self, action: action)
    }
    @objc private func reveal() {
        guard let selection else { return }
        NSWorkspace.shared.activateFileViewerSelecting([selection.directory])
    }
    @objc private func copyTranscript() {
        guard let displayedTranscript else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(displayedTranscript, forType: .string)
    }
    @objc private func retry() { if let selection { onRetry?(selection.directory, lease) } }
    @objc private func deferWork() { if let selection { onDefer?(selection.directory) } }
    @objc private func playMicrophone() { play(.microphone) }
    @objc private func playSystemAudio() { play(.systemAudio) }
    @objc private func playVideo() { play(.screen) }
    private func play(_ kind: SessionManifest.TrackKind) {
        guard let selection, let track = selection.manifest.tracks.first(where: { $0.kind == kind })
        else { return }
        let url = selection.directory.appendingPathComponent(track.filename)
        guard LocalFilePolicy.isNonemptyRegularFile(url),
            url.resolvingSymlinksInPath().deletingLastPathComponent()
                == selection.directory.resolvingSymlinksInPath()
        else { return }
        NSWorkspace.shared.open(url)
    }
}
