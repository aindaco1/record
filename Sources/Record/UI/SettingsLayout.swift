import AppKit

/// Standard responder editing for this menu-bar app's settings and session fields.
@MainActor
final class SettingsWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if let recorder = firstResponder as? ShortcutRecorderButton, recorder.isRecordingShortcut {
            recorder.keyDown(with: event)
            return true
        }
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let key = event.charactersIgnoringModifiers?.lowercased()
        if flags == .command {
            if key == "w" { performClose(nil); return true }
            let commands = ["a": "selectAll:", "c": "copy:", "x": "cut:", "v": "paste:"]
            if let key, let command = commands[key],
                firstResponder?.tryToPerform(NSSelectorFromString(command), with: self) == true
            {
                return true
            }
        }
        if key == "z", flags == .command || flags == [.command, .shift],
            let undo = firstResponder?.undoManager
        {
            if flags.contains(.shift), undo.canRedo { undo.redo(); return true }
            if !flags.contains(.shift), undo.canUndo { undo.undo(); return true }
        }
        return super.performKeyEquivalent(with: event)
    }
}

@MainActor
private final class SettingsDocumentView: NSView {
    override var isFlipped: Bool { true }
}

@MainActor
enum SettingsLayout {
    static func page(title: String, description: String, build: (NSStackView) -> Void) -> NSView {
        let document = SettingsDocumentView()
        document.translatesAutoresizingMaskIntoConstraints = false
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.documentView = document
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)
        stack.addArrangedSubview(heading(title, size: 24))
        stack.addArrangedSubview(note(description))
        build(stack)
        for view in stack.arrangedSubviews where !(view is NSButton) {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: document.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -28),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            document.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            document.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
        ])
        return scroll
    }

    static func row(_ label: String, _ views: NSView...) -> NSStackView {
        let text = NSTextField(labelWithString: label)
        text.alignment = .right
        text.widthAnchor.constraint(equalToConstant: 170).isActive = true
        let row = NSStackView(views: [text] + views)
        row.alignment = .centerY
        row.spacing = 12
        for view in views where !label.isEmpty && view is NSControl {
            view.setAccessibilityLabel(label)
        }
        return row
    }

    static func heading(_ title: String, size: CGFloat = 15) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: size, weight: .semibold)
        return label
    }

    static func note(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.textColor = .secondaryLabelColor
        return label
    }

    static func sidebarRow(_ title: String, symbol: String) -> NSView {
        let cell = NSTableCellView()
        let image = NSImageView(
            image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage())
        image.setAccessibilityElement(false)
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13)
        cell.imageView = image
        cell.textField = label
        for view in [image, label] {
            view.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(view)
        }
        NSLayoutConstraint.activate([
            image.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
            image.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            image.widthAnchor.constraint(equalToConstant: 18),
            image.heightAnchor.constraint(equalToConstant: 18),
            label.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }
}
