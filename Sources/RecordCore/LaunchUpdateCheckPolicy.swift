/// Decides whether the app should make its one explicit background update
/// check during updater startup. Keeping this policy independent of Sparkle
/// makes the launch behavior deterministic and testable without networking.
public enum LaunchUpdateCheckPolicy {
    public static func shouldCheckInBackground(
        startingUpdater: Bool,
        automaticallyChecksForUpdates: Bool
    ) -> Bool {
        startingUpdater && automaticallyChecksForUpdates
    }
}
