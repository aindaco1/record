import Sparkle

@MainActor
protocol UpdateChecking: AnyObject {
    func checkForUpdates()
}

/// Owns Sparkle's standard, signed update flow. Network access and installation
/// are delegated to Sparkle's narrowly scoped XPC services; Record itself keeps
/// its local-only sandbox boundary.
@MainActor
final class AppUpdateController: UpdateChecking {
    private let updaterController: SPUStandardUpdaterController

    init(startingUpdater: Bool = true) {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: startingUpdater,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}
