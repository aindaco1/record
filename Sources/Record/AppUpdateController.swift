import DustWaveUpdates
@MainActor
protocol UpdateChecking: AnyObject {
    func checkForUpdates()
}

/// Product adapter; Sparkle lifecycle and launch policy are shared in Platform.
@MainActor
final class AppUpdateController: UpdateChecking {
    private let updates: DustWaveUpdates.AppUpdateController

    init(startingUpdater: Bool = true) {
        updates = DustWaveUpdates.AppUpdateController(
            startingUpdater: startingUpdater, checkingOnLaunch: true)
    }

    func checkForUpdates() { updates.checkForUpdates() }
}
