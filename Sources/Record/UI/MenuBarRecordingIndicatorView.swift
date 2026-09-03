import AppKit
import QuartzCore

/// A separate colored layer leaves the camera's template rendering and the
/// status button's hit target intact. Only the red dot changes opacity.
@MainActor
final class MenuBarRecordingIndicatorView: NSView {
    static let dotDiameter: CGFloat = 5
    let dotLayer = CAShapeLayer()
    private var recording = false
    private var reduceMotion = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        dotLayer.fillColor = NSColor.systemRed.cgColor
        dotLayer.strokeColor = NSColor.white.cgColor
        dotLayer.lineWidth = 0.75
        layer?.addSublayer(dotLayer)
        isHidden = true
        setAccessibilityElement(false)
    }

    convenience init() {
        self.init(frame: NSRect(origin: .zero, size: MenuBarController.menuBarImageSize))
    }

    required init?(coder: NSCoder) { nil }

    // The overlay must never steal menu clicks, including clicks on the dot.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // Anchor the dot's center within the lower-right camera body.
        dotLayer.frame = CGRect(
            x: bounds.maxX - 9 - Self.dotDiameter / 2,
            y: bounds.minY + 5 - Self.dotDiameter / 2,
            width: Self.dotDiameter,
            height: Self.dotDiameter
        )
        dotLayer.path = CGPath(
            ellipseIn: dotLayer.bounds.insetBy(dx: 0.5, dy: 0.5), transform: nil
        )
        CATransaction.commit()
    }

    func update(recording: Bool, reduceMotion: Bool) {
        guard self.recording != recording || self.reduceMotion != reduceMotion else { return }
        self.recording = recording
        self.reduceMotion = reduceMotion
        isHidden = !recording
        dotLayer.removeAnimation(forKey: MenuBarController.recordingPulseAnimationKey)
        dotLayer.opacity = 1
        guard recording, !reduceMotion else { return }
        let animation = MenuBarController.recordingPulseAnimation()
        animation.beginTime = CACurrentMediaTime()
        dotLayer.add(animation, forKey: MenuBarController.recordingPulseAnimationKey)
    }
}
