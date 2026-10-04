import AppKit
import RecordCore

@MainActor
final class RecentSessionsViewController: NSViewController, NSTableViewDataSource,
    NSTableViewDelegate, NSSearchFieldDelegate
{
    private let search = NSSearchField()
    private let table = NSTableView()
    private let preview = NSTextView()
    private var displayedTranscript: String?
    private(set) var activeProgress: (session: String, stage: String)?
    private let variant = NSSegmentedControl(
        labels: [
            L10n.text("Transcript"), L10n.text("Before vocabulary"), L10n.text("Raw transcript"),
        ],
        trackingMode: .selectOne, target: nil, action: nil)
    private let status = NSTextField(wrappingLabelWithString: "")
    private lazy var revealButton = button(L10n.text("Reveal"), #selector(reveal))
    private lazy var copyButton = button(L10n.text("Copy transcript"), #selector(copyTranscript))
    private lazy var retryButton = button(L10n.text("Retry unfinished tracks"), #selector(retry))
    private lazy var vocabularyButton = button(
        L10n.text("Apply Vocabulary"), #selector(applyVocabulary))
    private lazy var deferButton = button(L10n.text("Transcribe later"), #selector(deferWork))
    private lazy var microphoneButton = button(
        L10n.text("Play microphone"), #selector(playMicrophone))
    private lazy var systemButton = button(
        L10n.text("Play system audio"), #selector(playSystemAudio))
    private lazy var importedButton = button(
        L10n.text("Play imported audio"), #selector(playImportedAudio))
    private lazy var importButton = button(L10n.text("Import Audio…"), #selector(importAudio))
    private lazy var videoButton = button(L10n.text("Play video"), #selector(playVideo))
    private var sessions: [RecentRecordingLocator.Candidate] = []
    private var filtered: [RecentRecordingLocator.Candidate] = []
    private var lease: ExportDirectoryLease?
    private var refreshTask: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
    private var roots: [URL] = []
    var onImport: (() -> Void)?
    var onRetry: ((URL, ExportDirectoryLease?) -> Void)?
    var onDefer: ((URL) -> Void)?
    var onApplyVocabulary: ((URL, ExportDirectoryLease?) -> Void)?

    init() { super.init(nibName: nil, bundle: nil) }
    override func loadView() {
        view = NSView()
        search.placeholderString = L10n.text("Filter by title or date (YYYY-MM-DD)")
        search.delegate = self
        search.setAccessibilityLabel(L10n.text("Filter sessions by title or date"))
        table.addTableColumn(NSTableColumn(identifier: .init("session")))
        table.headerView = nil
        table.rowHeight = 54
        table.delegate = self
        table.dataSource = self
        table.setAccessibilityLabel(L10n.text("Recent recording sessions"))
        let list = NSScrollView()
        list.documentView = table
        list.hasVerticalScroller = true
        list.heightAnchor.constraint(equalToConstant: 200).isActive = true
        preview.isEditable = false
        preview.isSelectable = true
        preview.font = .systemFont(ofSize: 13)
        preview.textContainerInset = NSSize(width: 10, height: 10)
        preview.autoresizingMask = [.width]
        preview.setAccessibilityLabel(L10n.text("Transcript preview"))
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
            microphoneButton, systemButton, videoButton, importedButton,
            button(L10n.text("Refresh"), #selector(refresh)),
        ])
        let stack = NSStackView(views: [
            SettingsLayout.heading(L10n.text("Sessions"), size: 24),
            SettingsLayout.note(
                L10n.text("Recordings in the current save folder and private recovery storage.")),
            importButton, search, list, status, playback, variant, text, actions, vocabularyButton,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        let content = view
        do {
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
        showSelection()
    }

    @available(*, unavailable) required init?(coder: NSCoder) { nil }

    func update(roots: [URL], retaining lease: ExportDirectoryLease?) {
        _ = view
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

    func endBrowsing() {
        refreshTask?.cancel()
        previewTask?.cancel()
        lease = nil
        roots = []
        sessions = []
        filtered = []
        preview.string = ""
        displayedTranscript = nil
        table.reloadData()
        showSelection()
    }

    @objc func refresh() {
        guard !roots.isEmpty else { return }
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
        let duration =
            session.manifest.importedAudio.map { $0.durationMilliseconds / 1_000 }
            ?? max(
                0,
                Int(
                    (session.manifest.endedAt ?? session.manifest.startedAt)
                        .timeIntervalSince(session.manifest.startedAt)))
        let kind =
            session.manifest.importedAudio != nil
            ? L10n.text("Imported audio")
            : session.manifest.tracks.contains { $0.kind == .screen }
                ? L10n.text("Screen") : L10n.text("Audio")
        let transcription =
            session.transcription.map {
                $0.state.title + " \($0.completedTracks)/\($0.tracks.count)"
            }
            ?? (session.hasTranscript ? L10n.text("transcribed") : L10n.text("no transcript"))
        let label = NSTextField(
            wrappingLabelWithString: "\(session.directory.lastPathComponent)\n"
                + "\(session.manifest.startedAt.formatted(date: .numeric, time: .shortened)) · \(duration / 60):"
                + String(format: "%02d", duration % 60)
                + " · \(kind) · \(session.manifest.state.displayTitle) · \(transcription)")
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
        vocabularyButton.isEnabled =
            selection?.hasTranscript == true
            && selection?.transcription?.state != .processing
        let mayTranscribe =
            selection.map {
                ($0.manifest.state == .finalized || $0.manifest.state == .interrupted)
                    && $0.manifest.tracks.contains {
                        $0.kind == .microphone || $0.kind == .systemAudio
                            || $0.kind == .importedAudio
                    }
                    && ($0.transcription.map { $0.state != .complete } ?? !$0.hasTranscript)
            } ?? false
        retryButton.isEnabled = mayTranscribe
        deferButton.isEnabled = mayTranscribe && selection?.transcription?.state != .deferred
        for (kind, button) in [
            (SessionManifest.TrackKind.microphone, microphoneButton),
            (.systemAudio, systemButton), (.screen, videoButton), (.importedAudio, importedButton),
        ] {
            button.isEnabled = selection?.manifest.tracks.contains { $0.kind == kind } == true
            button.isHidden = !button.isEnabled
        }
        guard let session = selection else {
            status.stringValue =
                sessions.isEmpty
                ? L10n.text("No sessions in the current save folder or private recovery storage.")
                : L10n.text("No sessions match this filter.")
            return
        }
        let filename = [
            "transcript.json", TranscriptVocabulary.cleanFilename, "transcript.raw.json",
        ][max(0, variant.selectedSegment)]
        let retainedLease = lease
        previewTask = Task { [weak self] in
            let result = await Task.detached(priority: .utility) { () -> (String, String?) in
                defer { withExtendedLifetime(retainedLease) {} }
                let checkpoint = try? TranscriptionCheckpoint.read(from: session.directory)
                let state =
                    checkpoint.map {
                        "\($0.state.title) · "
                            + $0.tracks.map {
                                "\(TranscriptionCoordinator.trackTitle($0.source.speaker)): \(L10n.text($0.segments != nil ? "complete" : "unfinished"))"
                            }.joined(separator: " · ")
                    }
                    ?? (session.hasTranscript
                        ? L10n.text("Transcript ready") : L10n.text("Transcription not started"))
                guard
                    let transcript = try? TranscriptPreviewReader.read(
                        directory: session.directory, filename: filename)
                else { return (state, nil) }
                return (state, transcript.rendered(title: session.directory.lastPathComponent))
            }.value
            guard !Task.isCancelled else { return }
            if self?.activeProgress?.session == session.directory.lastPathComponent {
                self?.status.stringValue = self?.activeProgress?.stage ?? result.0
            } else {
                self?.status.stringValue = result.0
            }
            self?.displayedTranscript = result.1
            self?.copyButton.isEnabled = result.1 != nil
            self?.preview.string =
                result.1
                ?? L10n.text(
                    "No preview is available. Use Reveal to inspect the session and its source files."
                )
        }
    }

    func updateTranscription(_ update: TranscriptionCoordinator.Status, isVisible: Bool) {
        switch update {
        case .progress(let session, let stage, _):
            activeProgress = (session, stage)
            if selection?.directory.lastPathComponent == session { status.stringValue = stage }
        default:
            activeProgress = nil
            if isVisible { refresh() }
        }
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
    func setImporting(_ importing: Bool) { importButton.isEnabled = !importing }
    @objc private func importAudio() { onImport?() }
    @objc private func playImportedAudio() { play(.importedAudio) }
    func showMessage(_ message: String) { status.stringValue = message }
    @objc private func applyVocabulary() {
        if let selection { onApplyVocabulary?(selection.directory, lease) }
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
