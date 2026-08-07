import RecordSpeech

/// Defense in depth for FluidAudio, whose model APIs include download paths.
/// The signed app sandbox remains the outer enforcement boundary.
enum FluidAudioOfflinePolicy {
    static func enforce() {
        RecordFluidAudioOfflinePolicy.enforce()
    }

    static var isEnforced: Bool {
        RecordFluidAudioOfflinePolicy.isEnforced
    }
}
