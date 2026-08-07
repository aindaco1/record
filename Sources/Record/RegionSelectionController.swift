import AppKit
import CoreGraphics
import Foundation
import RecordCapture
import RecordCore

enum RegionSelectionError: Error, Equatable {
    case alreadyPresenting
    case cancelled
    case displayUnavailable
    case invalidRegion
}

struct RegionSelectionGeometry {
    static func captureRect(
        from viewRect: CGRect,
        viewSize: CGSize,
        contentSize: CGSize
    ) throws -> CaptureRect {
        let rect = viewRect.standardized
        guard viewSize.width > 0, viewSize.height > 0,
            contentSize.width > 0, contentSize.height > 0,
            rect.width >= 16, rect.height >= 16,
            rect.minX >= 0, rect.minY >= 0,
            rect.maxX <= viewSize.width, rect.maxY <= viewSize.height
        else {
            throw RegionSelectionError.invalidRegion
        }
        let scaleX = contentSize.width / viewSize.width
        let scaleY = contentSize.height / viewSize.height
        return CaptureRect(
            x: rect.minX * scaleX,
            y: (viewSize.height - rect.maxY) * scaleY,
            width: rect.width * scaleX,
            height: rect.height * scaleY
        )
    }
}

/// A short-lived, noncapturing overlay used after the system picker selects a
/// display. It emits only display-local geometry and never takes a screenshot.
@MainActor
final class RegionSelectionController {
    private var continuation: CheckedContinuation<CaptureRect, any Error>?
    private var panel: NSPanel?

    func selectRegion(
        for selection: SystemScreenCaptureSelection
    ) async throws -> CaptureRect {
        guard continuation == nil else { throw RegionSelectionError.alreadyPresenting }
        guard selection.plan.style == .display,
            let screen = Self.screen(for: selection)
        else {
            throw RegionSelectionError.displayUnavailable
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                let view = RegionSelectionView(frame: .init(origin: .zero, size: screen.frame.size))
                view.onComplete = { [weak self, weak view] result in
                    guard let self, let view else { return }
                    do {
                        let rect = try result.get()
                        let captureRect = try RegionSelectionGeometry.captureRect(
                            from: rect,
                            viewSize: view.bounds.size,
                            contentSize: CGSize(
                                width: selection.plan.contentRect.width,
                                height: selection.plan.contentRect.height
                            )
                        )
                        self.finish(.success(captureRect))
                    } catch {
                        self.finish(.failure(error))
                    }
                }

                let panel = NSPanel(
                    contentRect: screen.frame,
                    styleMask: [.borderless],
                    backing: .buffered,
                    defer: false,
                    screen: screen
                )
                panel.level = .screenSaver
                panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                panel.backgroundColor = .clear
                panel.isOpaque = false
                panel.hasShadow = false
                panel.contentView = view
                panel.makeFirstResponder(view)
                NSApp.activate(ignoringOtherApps: true)
                panel.makeKeyAndOrderFront(nil)
                self.panel = panel
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.finish(.failure(CancellationError()))
            }
        }
    }

    private func finish(_ result: Result<CaptureRect, any Error>) {
        guard let continuation else { return }
        self.continuation = nil
        panel?.orderOut(nil)
        panel = nil
        continuation.resume(with: result)
    }

    private static func screen(
        for selection: SystemScreenCaptureSelection
    ) -> NSScreen? {
        let candidates: [(screen: NSScreen, id: UInt32)] = NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[.init("NSScreenNumber")] as? NSNumber
            else { return nil }
            return (screen, number.uint32Value)
        }
        if let selectedDisplayID = selection.selectedDisplayID {
            return candidates.first { $0.id == selectedDisplayID }?.screen
        }

        let selected = selection.plan.contentRect
        let tolerance = 1.0
        let matches = candidates.filter { candidate in
            let bounds = CGDisplayBounds(candidate.id)
            return abs(bounds.origin.x - selected.x) <= tolerance
                && abs(bounds.origin.y - selected.y) <= tolerance
                && abs(bounds.width - selected.width) <= tolerance
                && abs(bounds.height - selected.height) <= tolerance
        }
        return matches.count == 1 ? matches[0].screen : nil
    }
}

@MainActor
private final class RegionSelectionView: NSView {
    var onComplete: ((Result<CGRect, any Error>) -> Void)?
    private var anchor: CGPoint?
    private var selection: CGRect?

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.28).setFill()
        bounds.fill()

        if let selection {
            NSColor.controlAccentColor.withAlphaComponent(0.22).setFill()
            selection.fill()
            NSColor.white.setStroke()
            let border = NSBezierPath(rect: selection.insetBy(dx: 0.5, dy: 0.5))
            border.lineWidth = 2
            border.stroke()
        }

        let message = "Drag to select a recording region · Esc to cancel"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
            .foregroundColor: NSColor.white,
            .backgroundColor: NSColor.black.withAlphaComponent(0.65),
        ]
        let size = message.size(withAttributes: attributes)
        message.draw(
            at: CGPoint(x: bounds.midX - size.width / 2, y: bounds.maxY - size.height - 36),
            withAttributes: attributes
        )
    }

    override func mouseDown(with event: NSEvent) {
        anchor = convert(event.locationInWindow, from: nil)
        selection = nil
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let anchor else { return }
        let current = convert(event.locationInWindow, from: nil)
        selection = CGRect(
            x: min(anchor.x, current.x),
            y: min(anchor.y, current.y),
            width: abs(current.x - anchor.x),
            height: abs(current.y - anchor.y)
        ).intersection(bounds)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let selection, selection.width >= 16, selection.height >= 16 else {
            NSSound.beep()
            return
        }
        onComplete?(.success(selection))
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onComplete?(.failure(RegionSelectionError.cancelled))
        } else {
            super.keyDown(with: event)
        }
    }
}
