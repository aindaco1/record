import AppKit
import RecordCore

/// A local editable list; the shared vocabulary owns validation and matching.
@MainActor
final class VocabularySettingsView: NSStackView, NSTableViewDataSource, NSTableViewDelegate {
    private var draft = VocabularyPreferences.current()
    private let table = NSTableView()
    private let message = NSTextField(wrappingLabelWithString: "")

    init() {
        super.init(frame: .zero)
        orientation = .vertical
        alignment = .leading
        spacing = 8
        for (id, title) in [
            ("preferred", L10n.text("Preferred spelling")),
            ("aliases", L10n.text("Other spellings (separate with ;) ")),
        ] {
            let column = NSTableColumn(identifier: .init(id))
            column.title = title
            column.minWidth = id == "preferred" ? 190 : 240
            column.width = id == "preferred" ? 190 : 290
            column.resizingMask =
                id == "preferred" ? .userResizingMask : [.autoresizingMask, .userResizingMask]
            column.isEditable = true
            table.addTableColumn(column)
        }
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.delegate = self
        table.dataSource = self
        table.rowHeight = 28
        table.setAccessibilityLabel(L10n.text("Global vocabulary"))
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        addArrangedSubview(scroll)
        scroll.heightAnchor.constraint(equalToConstant: 150).isActive = true
        scroll.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
        addArrangedSubview(
            NSStackView(views: [
                NSButton(title: L10n.text("Add word"), target: self, action: #selector(add)),
                NSButton(
                    title: L10n.text("Remove selected"), target: self, action: #selector(remove)),
                NSButton(
                    title: L10n.text("Save vocabulary"), target: self, action: #selector(save)),
            ]))
        addArrangedSubview(message)
        message.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
    }

    @available(*, unavailable) required init?(coder: NSCoder) { nil }

    func numberOfRows(in tableView: NSTableView) -> Int { draft.terms.count }
    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int)
        -> Any?
    {
        tableColumn?.identifier.rawValue == "preferred"
            ? draft.terms[row].preferred : draft.terms[row].aliases.joined(separator: "; ")
    }
    func tableView(
        _ tableView: NSTableView, setObjectValue object: Any?, for tableColumn: NSTableColumn?,
        row: Int
    ) {
        guard draft.terms.indices.contains(row), let text = object as? String else { return }
        if tableColumn?.identifier.rawValue == "preferred" {
            draft.terms[row].preferred = text.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            draft.terms[row].aliases = text.split(separator: ";").map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }.filter { !$0.isEmpty }
        }
        message.stringValue = L10n.text("Unsaved vocabulary changes")
    }
    @objc private func add() {
        guard draft.terms.count < 200 else { return }
        window?.makeFirstResponder(table)
        draft.terms.append(.init(preferred: ""))
        table.reloadData()
        let row = draft.terms.count - 1
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        table.scrollRowToVisible(row)
        table.editColumn(0, row: row, with: nil, select: true)
    }
    @objc private func remove() {
        window?.makeFirstResponder(table)
        guard draft.terms.indices.contains(table.selectedRow) else { return }
        draft.terms.remove(at: table.selectedRow)
        table.reloadData()
        message.stringValue = L10n.text("Unsaved vocabulary changes")
    }
    @objc private func save() {
        window?.makeFirstResponder(table)
        do {
            try VocabularyPreferences.save(draft)
            message.textColor = .secondaryLabelColor
            message.stringValue = L10n.text(
                "Vocabulary saved. New transcripts will use these spellings.")
        } catch {
            message.textColor = .systemRed
            message.stringValue = L10n.text(
                "Use unique, nonempty spellings up to 128 characters, with at most 20 aliases per word."
            )
        }
        AccessibilityAnnouncements.post(message.stringValue)
    }
}
