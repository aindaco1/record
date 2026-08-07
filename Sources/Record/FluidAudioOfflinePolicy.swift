import FluidAudio

/// Defense in depth for FluidAudio, whose model APIs include download paths.
/// The signed app sandbox remains the outer enforcement boundary.
enum FluidAudioOfflinePolicy {
    static func enforce() {
        ModelHub.offlineMode = true
    }

    static var isEnforced: Bool {
        ModelHub.offlineMode
    }
}
