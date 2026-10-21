import AppKit

protocol ZoomActivityMonitoring: AnyObject {
    var isZoomRunning: Bool { get }
    func start(onChange: @escaping @Sendable (Bool) -> Void)
    func stop()
}

/// Checks only Zoom's app identity, including background instances. No window,
/// meeting, microphone, or other application information is inspected or saved.
/// Observer lifecycle and callbacks are confined to the main queue.
final class ZoomApplicationMonitor: ZoomActivityMonitoring, @unchecked Sendable {
    private let notificationCenter: NotificationCenter
    private let running: () -> Bool
    private var observers: [NSObjectProtocol] = []

    init(
        notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        running: @escaping () -> Bool = {
            !NSRunningApplication.runningApplications(withBundleIdentifier: "us.zoom.xos").isEmpty
        }
    ) {
        self.notificationCenter = notificationCenter
        self.running = running
    }

    var isZoomRunning: Bool { running() }

    func start(onChange: @escaping @Sendable (Bool) -> Void) {
        dispatchPrecondition(condition: .onQueue(.main))
        stop()
        for name in [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
        ] {
            observers.append(
                notificationCenter.addObserver(forName: name, object: nil, queue: .main) {
                    [weak self] _ in
                    guard let self else { return }
                    onChange(self.isZoomRunning)
                })
        }
        // Subscribe before sampling so a launch cannot be lost between the two.
        onChange(isZoomRunning)
    }

    func stop() {
        for observer in observers { notificationCenter.removeObserver(observer) }
        observers.removeAll()
    }

    deinit { stop() }
}
