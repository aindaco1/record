import Foundation
import RecordCore

public struct ScreenCaptureSourceInventory: Equatable, Sendable {
    public struct Display: Equatable, Sendable {
        public let id: UInt32
        public let width: Int
        public let height: Int

        public init(id: UInt32, width: Int, height: Int) {
            self.id = id
            self.width = width
            self.height = height
        }
    }

    public let displays: [Display]
    public let applicationBundleIdentifiers: Set<String>
    public let windowIDs: Set<UInt32>

    public init(
        displays: [Display],
        applicationBundleIdentifiers: Set<String>,
        windowIDs: Set<UInt32>
    ) {
        self.displays = displays
        self.applicationBundleIdentifiers = applicationBundleIdentifiers
        self.windowIDs = windowIDs
    }

    @discardableResult
    public func resolve(_ source: CaptureSource) throws -> CaptureSource {
        switch source {
        case .display(let id):
            guard display(id: id) != nil else {
                throw ScreenCaptureAdapterError.sourceUnavailable(source)
            }

        case .application(let bundleIdentifier, let displayID):
            guard display(id: displayID) != nil,
                applicationBundleIdentifiers.contains(bundleIdentifier)
            else {
                throw ScreenCaptureAdapterError.sourceUnavailable(source)
            }

        case .window(let id):
            guard windowIDs.contains(id) else {
                throw ScreenCaptureAdapterError.sourceUnavailable(source)
            }

        case .region(let displayID, let rect):
            guard let display = display(id: displayID) else {
                throw ScreenCaptureAdapterError.sourceUnavailable(source)
            }
            guard rect.x + rect.width <= Double(display.width),
                rect.y + rect.height <= Double(display.height)
            else {
                throw ScreenCaptureAdapterError.regionOutsideDisplay(
                    displayID: displayID,
                    rect: rect
                )
            }
        }
        return source
    }

    private func display(id: UInt32) -> Display? {
        displays.first { $0.id == id }
    }
}

public enum ScreenCaptureAdapterError: Error, Equatable {
    case invalidQueueDepth(Int)
    case sourceUnavailable(CaptureSource)
    case regionOutsideDisplay(displayID: UInt32, rect: CaptureRect)
    case captureFailed(CaptureFailure)
    case invalidState(ScreenCaptureSession.State)
}
