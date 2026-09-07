/// A stream starting does not establish that every requested writer has media.
/// Keep Resume in progress until each required track has accepted a sample.
public struct CaptureStartupReadiness: Sendable {
    private let requiredTracks: Set<SessionManifest.TrackKind>

    public init(audio: CaptureAudioConfiguration) {
        var tracks: Set<SessionManifest.TrackKind> = [.screen]
        if audio.includeSystemAudio { tracks.insert(.systemAudio) }
        if audio.includeMicrophone { tracks.insert(.microphone) }
        requiredTracks = tracks
    }

    public func isReady(processedTracks: Set<SessionManifest.TrackKind>) -> Bool {
        requiredTracks.isSubset(of: processedTracks)
    }
}
