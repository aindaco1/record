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

struct RegionSelection: Equatable, Sendable {
    let displayID: UInt32
    let rect: CaptureRect
    let pointPixelScale: Double
}

/// Short-lived, noncapturing overlays on the connected displays. The display
/// where the user drags becomes the source; Record emits only display-local
/// geometry and never takes a screenshot during selection.
@MainActor
final class RegionSelectionController {
    private struct Display {
        let id: UInt32
        let screen: NSScreen
        let pointPixelScale: Double
    }

    private var continuation: CheckedContinuation<RegionSelection, any Error>?
    private var panels: [NSPanel] = []

    func selectRegion() async throws -> RegionSelection {
        guard continuation == nil else { throw RegionSelectionError.alreadyPresenting }
        let displays = Self.displays()
        guard !displays.isEmpty else {
            throw RegionSelectionError.displayUnavailable
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                var overlays: [(panel: RegionSelectionPanel, view: RegionSelectionView)] = []
                for display in displays {
                    let view = RegionSelectionView(
                        frame: .init(origin: .zero, size: display.screen.frame.size)
                    )
                    view.onComplete = { [weak self, weak view] result in
                        guard let self, let view else { return }
                        do {
                            let rect = try result.get()
                            let captureRect = try RegionSelectionGeometry.captureRect(
                                from: rect,
                                viewSize: view.bounds.size,
                                contentSize: view.bounds.size
                            )
                            self.finish(
                                .success(
                                    .init(
                                        displayID: display.id,
                                        rect: captureRect,
                                        pointPixelScale: display.pointPixelScale
                                    )
                                )
                            )
                        } catch {
                            self.finish(.failure(error))
                        }
                    }

                    let panel = RegionSelectionPanel(
                        contentRect: display.screen.frame,
                        styleMask: [.borderless],
                        backing: .buffered,
                        defer: false,
                        screen: display.screen
                    )
                    panel.configureForRegionSelection()
                    panel.contentView = view
                    overlays.append((panel, view))
                }

                self.panels = overlays.map(\.panel)
                NSApp.activate(ignoringOtherApps: true)
                for overlay in overlays {
                    overlay.panel.orderFrontRegardless()
                }

                let mouseLocation = NSEvent.mouseLocation
                let preferred =
                    overlays.first { $0.panel.frame.contains(mouseLocation) }
                    ?? overlays.first
                preferred?.panel.makeKey()
                preferred?.panel.makeFirstResponder(preferred?.view)
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.finish(.failure(CancellationError()))
            }
        }
    }

    private func finish(_ result: Result<RegionSelection, any Error>) {
        guard let continuation else { return }
        self.continuation = nil
        for panel in panels {
            panel.orderOut(nil)
        }
        panels.removeAll()
        continuation.resume(with: result)
    }

    private static func displays() -> [Display] {
        NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[.init("NSScreenNumber")] as? NSNumber
            else { return nil }
            let displayID = number.uint32Value
            let pointPixelScale = screen.backingScaleFactor
            guard displayID > 0, pointPixelScale.isFinite, pointPixelScale > 0 else {
                return nil
            }
            return .init(
                id: displayID,
                screen: screen,
                pointPixelScale: pointPixelScale
            )
        }
    }
}

@MainActor
final class RegionSelectionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    func configureForRegionSelection() {
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = false
        isMovable = false
        isMovableByWindowBackground = false

        // Status-item apps normally deactivate as soon as their menu closes,
        // and NSPanel hides on deactivation by default. Region selection must
        // stay visible and interactive during that expected transition.
        hidesOnDeactivate = false
    }
}

@MainActor
final class RegionSelectionView: NSView {
    var onComplete: ((Result<CGRect, any Error>) -> Void)?
    private var anchor: CGPoint?
    private var selection: CGRect?

    override var acceptsFirstResponder: Bool { true }

    // Transparent views default to allowing mouse-down events to move their
    // window. This overlay is intentionally transparent, so it must explicitly
    // retain the complete down/drag/up sequence used to draw a region.
    override var mouseDownCanMoveWindow: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

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

        let message = "Drag to select a capture area · Esc to cancel"
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
