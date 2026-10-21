/// Per-capture voice-processing policy. Zoom protection latches until capture
/// ends so quitting/relaunching Zoom cannot repeatedly rebuild the audio graph.
public struct MicrophoneVoiceProcessingPolicy: Sendable {
    public let requested: Bool
    public let disableForZoom: Bool
    public private(set) var bypassedForZoom = false

    public init(requested: Bool = true, disableForZoom: Bool = true) {
        self.requested = requested
        self.disableForZoom = disableForZoom
    }

    public mutating func reset() {
        bypassedForZoom = false
    }

    /// Returns true only when this observation first requires a raw-input path.
    @discardableResult
    public mutating func observeZoom(isRunning: Bool) -> Bool {
        guard requested, disableForZoom, isRunning, !bypassedForZoom else { return false }
        bypassedForZoom = true
        return true
    }

    public func usesVoiceProcessing(deviceID: String?) -> Bool {
        MicrophoneSelectionPolicy.usesVoiceProcessing(
            requested: requested && !bypassedForZoom, deviceID: deviceID)
    }
}
