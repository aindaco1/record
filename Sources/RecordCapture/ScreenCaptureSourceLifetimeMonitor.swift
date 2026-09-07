import AppKit
import RecordCore

/// SCStream can keep delivering audio after the selected application exits.
/// Observe that application's lifetime independently of screen frame activity:
/// idle, hidden, minimized, and off-Space windows are still valid sources.
@MainActor
final class ScreenCaptureSourceLifetimeMonitor {
    private let processIDs: Set<Int32>
    private let notificationCenter: NotificationCenter
    private let applicationIsRunning: (Int32) -> Bool
    private let onFailure: @Sendable (CaptureFailure) -> Void
    private var lifetime: CaptureSourceLifetime
    private var observation: ApplicationTerminationObservation?

    init(
        processIDs: Set<Int32>,
        notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        applicationIsRunning: @escaping (Int32) -> Bool = {
            NSRunningApplication(processIdentifier: $0).map { !$0.isTerminated } ?? false
        },
        onFailure: @escaping @Sendable (CaptureFailure) -> Void
    ) {
        self.processIDs = processIDs
        self.notificationCenter = notificationCenter
        self.applicationIsRunning = applicationIsRunning
        self.onFailure = onFailure
        lifetime = CaptureSourceLifetime(processIDs: processIDs)
    }

    func start() throws {
        guard observation == nil, !processIDs.isEmpty else { return }
        observation = ApplicationTerminationObservation(center: notificationCenter) {
            [weak self] processID in
            Task { @MainActor [weak self] in
                guard let self,
                    let failure = self.lifetime.applicationTerminated(processID: processID)
                else { return }
                self.onFailure(failure)
            }
        }
        // Register first, then check for an exit between selection and startup.
        for processID in processIDs where !applicationIsRunning(processID) {
            if let failure = lifetime.applicationTerminated(processID: processID) {
                stop()
                throw ScreenCaptureAdapterError.captureFailed(failure)
            }
        }
    }

    func stop() {
        lifetime.cancel()
        observation = nil
    }
}

/// NotificationCenter supports removing observers from any thread. Owning the
/// token separately also guarantees cleanup when a prepared stream is released.
private final class ApplicationTerminationObservation: @unchecked Sendable {
    private let center: NotificationCenter
    private let token: any NSObjectProtocol

    init(center: NotificationCenter, onTermination: @escaping @Sendable (Int32) -> Void) {
        self.center = center
        token = center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: nil
        ) { notification in
            guard
                let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication
            else { return }
            onTermination(application.processIdentifier)
        }
    }

    deinit { center.removeObserver(token) }
}
