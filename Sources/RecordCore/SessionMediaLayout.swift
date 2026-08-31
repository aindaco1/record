import Foundation

/// Canonical filenames and anonymous speaker labels shared by capture,
/// finalization, inspection, transcription, and export.
public enum SessionMediaLayout {
    public enum Stage: Sendable {
        case capture
        case finalized
    }

    public static func filename(
        for kind: SessionManifest.TrackKind,
        stage: Stage
    ) -> String? {
        switch (kind, stage) {
        case (.screen, _):
            return "recording.mov"
        case (.microphone, .capture):
            return "mic.caf"
        case (.microphone, .finalized):
            return "mic.wav"
        case (.systemAudio, .capture):
            return "system.caf"
        case (.systemAudio, .finalized):
            return "system.wav"
        case (.camera, _):
            return nil
        }
    }

    public static func defaultSpeaker(for kind: SessionManifest.TrackKind) -> String? {
        switch kind {
        case .microphone:
            return "me"
        case .systemAudio:
            return "them"
        case .screen, .camera:
            return nil
        }
    }

    public static func url(
        for kind: SessionManifest.TrackKind,
        stage: Stage,
        in directory: URL
    ) -> URL? {
        filename(for: kind, stage: stage).map {
            directory.appendingPathComponent($0, isDirectory: false)
        }
    }

    public static func track(
        for kind: SessionManifest.TrackKind,
        stage: Stage,
        startOffsetMilliseconds: Int = 0
    ) -> SessionManifest.Track? {
        guard let filename = filename(for: kind, stage: stage) else { return nil }
        return SessionManifest.Track(
            kind: kind,
            filename: filename,
            speaker: defaultSpeaker(for: kind),
            startOffsetMilliseconds: startOffsetMilliseconds
        )
    }
}
