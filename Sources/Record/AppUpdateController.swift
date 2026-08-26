import RecordCore
import Sparkle

@MainActor
protocol UpdateChecking: AnyObject {
    func checkForUpdates()
}

/// Owns Sparkle's standard, signed update flow. A silent check runs once when
/// the app launches; presenting and installing an update remain user driven.
/// Network access and installation are delegated to Sparkle's narrowly scoped
/// XPC services, so Record itself keeps its local-only sandbox boundary.
@MainActor
final class AppUpdateController: UpdateChecking {
    private let updaterController: SPUStandardUpdaterController

    init(startingUpdater: Bool = true) {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: startingUpdater,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        if LaunchUpdateCheckPolicy.shouldCheckInBackground(
            startingUpdater: startingUpdater,
            automaticallyChecksForUpdates: updaterController.updater.automaticallyChecksForUpdates
        ) {
            updaterController.updater.checkForUpdatesInBackground()
        }
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}
