import AppKit
import Foundation

struct ScreenshotDisplayDescriptor: Equatable, Sendable {
    let id: UInt32
    let frame: CGRect
}

enum ScreenshotDisplayLocator {
    static func displayID(
        containing point: CGPoint,
        displays: [ScreenshotDisplayDescriptor]
    ) -> UInt32? {
        displays.first { $0.frame.contains(point) }?.id
            ?? displays.first?.id
    }

    @MainActor
    static func displayID(containing point: CGPoint = NSEvent.mouseLocation) -> UInt32? {
        displayID(
            containing: point,
            displays: NSScreen.screens.compactMap { screen in
                guard
                    let number = screen.deviceDescription[.init("NSScreenNumber")]
                        as? NSNumber,
                    number.uint32Value > 0
                else { return nil }
                return .init(id: number.uint32Value, frame: screen.frame)
            }
        )
    }
}
