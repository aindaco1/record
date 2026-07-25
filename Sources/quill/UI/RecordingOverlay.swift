import AppKit
import SwiftUI

/// Borderless, click-through orange pill top-center of the active screen —
/// a persistent "recording" indicator with a live mic waveform (the system's
/// own mic capsule collapses to a dot after a moment; this one stays up for
/// the whole session). Adapted from parrot's RecordingOverlay.
@MainActor
final class RecordingOverlay {
    private var window: NSPanel?
    private let model = OverlayModel()

    func show() {
        ensureWindow()
        model.resetLevels()
        guard let window else { return }
        if !window.isVisible {
            positionAtTopCenter(window)
            window.orderFrontRegardless()
            // Defer the state change so SwiftUI lays out in the hidden style
            // first, then animates to visible on the next runloop tick.
            DispatchQueue.main.async { [model] in
                model.visible = true
            }
        } else {
            model.visible = true
        }
    }

    func hide() {
        model.visible = false
        // Let the scale+fade animation play out before yanking the window.
        let window = self.window
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            window?.orderOut(nil)
        }
    }

    /// Push a new audio level (0…~1). Safe to call from any thread.
    nonisolated func pushLevel(_ level: Float) {
        Task { @MainActor in
            self.model.pushLevel(level)
        }
    }

    private func ensureWindow() {
        if window != nil { return }
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 96, height: 36),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false

        let host = NSHostingView(rootView: OverlayPill(model: model))
        host.frame = panel.contentView?.bounds ?? .zero
        host.autoresizingMask = [.width, .height]
        panel.contentView = host

        window = panel
    }

    private func positionAtTopCenter(_ window: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let frame = window.frame
        let visible = screen.visibleFrame
        let x = visible.midX - frame.width / 2
        let y = visible.maxY - frame.height - 6
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

/// Observable state for the SwiftUI pill.
@MainActor
final class OverlayModel: ObservableObject {
    static let barCount = 6
    /// Per-bar height multiplier — center bars peak higher than edge bars.
    private static let envelope: [Float] = [0.55, 0.85, 1.0, 1.0, 0.85, 0.55]

    @Published var visible = false
    @Published var levels: [Float] = Array(repeating: 0, count: barCount)

    func pushLevel(_ level: Float) {
        let shaped = min(1.0, sqrt(max(0, level)) * 3.4)
        var next = [Float]()
        next.reserveCapacity(Self.barCount)
        for i in 0..<Self.barCount {
            // Small per-bar jitter so the bars don't all move in lockstep.
            let jitter = Float.random(in: 0.78...1.0)
            next.append(shaped * Self.envelope[i] * jitter)
        }
        levels = next
    }

    func resetLevels() {
        levels = Array(repeating: 0, count: Self.barCount)
    }
}

private struct OverlayPill: View {
    @ObservedObject var model: OverlayModel

    var body: some View {
        Waveform(levels: model.levels)
            .frame(width: 54, height: 18)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Capsule().fill(Color(nsColor: .systemOrange)))
            .scaleEffect(model.visible ? 1 : 0)
            .animation(
                .timingCurve(0.16, 1, 0.3, 1, duration: 0.3),
                value: model.visible
            )
    }
}

private struct Waveform: View {
    let levels: [Float]

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                Capsule()
                    .fill(Color.white)
                    .frame(width: 2.5)
                    .frame(maxHeight: .infinity)
                    .scaleEffect(y: max(0.10, CGFloat(level)), anchor: .center)
                    .animation(.easeOut(duration: 0.09), value: level)
            }
        }
    }
}
