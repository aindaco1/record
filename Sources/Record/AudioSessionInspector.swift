import ArgumentParser
import AVFoundation
import Foundation
import RecordCore

struct AudioTrackInspection: Equatable {
    let kind: SessionManifest.TrackKind
    let filename: String
    let byteCount: UInt64
    let durationSeconds: Double
    let startOffsetMilliseconds: Int
}

struct AudioSessionInspection: Equatable {
    let startedAt: Date
    let endedAt: Date
    let tracks: [AudioTrackInspection]
}

enum AudioSessionInspector {
    enum InspectionError: Error, CustomStringConvertible {
        case notFinalized(SessionManifest.State)
        case missingEndTimestamp
        case missingTrack(SessionManifest.TrackKind)
        case duplicateTrack(SessionManifest.TrackKind)
        case unsafeFilename(String)
        case unexpectedFilename(kind: SessionManifest.TrackKind, filename: String)
        case negativeOffset(kind: SessionManifest.TrackKind, milliseconds: Int)
        case missingOrEmptyFile(String)
        case unreadableAudio(String)

        var description: String {
            switch self {
            case .notFinalized(let state):
                return "session is not finalized: \(state.rawValue)"
            case .missingEndTimestamp:
                return "finalized session has no end timestamp"
            case .missingTrack(let kind):
                return "session is missing its \(kind.rawValue) track"
            case .duplicateTrack(let kind):
                return "session contains multiple \(kind.rawValue) tracks"
            case .unsafeFilename(let filename):
                return "session contains an unsafe track filename: \(filename)"
            case .unexpectedFilename(let kind, let filename):
                return "unexpected \(kind.rawValue) filename: \(filename)"
            case .negativeOffset(let kind, let milliseconds):
                return "negative \(kind.rawValue) start offset: \(milliseconds) ms"
            case .missingOrEmptyFile(let filename):
                return "missing or empty audio track: \(filename)"
            case .unreadableAudio(let filename):
                return "audio track has no readable duration: \(filename)"
            }
        }
    }

    static func inspect(sessionDirectory: URL) throws -> AudioSessionInspection {
        let manifest: SessionManifest
        do {
            manifest = try SessionManifest.read(from: sessionDirectory)
        } catch SessionManifest.ManifestError.unsafeTrackFilename(let filename) {
            throw InspectionError.unsafeFilename(filename)
        }
        guard manifest.state == .finalized else {
            throw InspectionError.notFinalized(manifest.state)
        }
        guard let endedAt = manifest.endedAt else {
            throw InspectionError.missingEndTimestamp
        }

        let expectedTracks: [(SessionManifest.TrackKind, String)] = [
            (.microphone, "mic.caf"),
            (.systemAudio, "system.caf"),
        ]
        let inspections = try expectedTracks.map { kind, expectedFilename in
            let matching = manifest.tracks.filter { $0.kind == kind }
            guard let track = matching.first else {
                throw InspectionError.missingTrack(kind)
            }
            guard matching.count == 1 else {
                throw InspectionError.duplicateTrack(kind)
            }
            guard URL(fileURLWithPath: track.filename).lastPathComponent == track.filename,
                !track.filename.contains("/"),
                track.filename != ".",
                track.filename != ".."
            else {
                throw InspectionError.unsafeFilename(track.filename)
            }
            guard track.filename == expectedFilename else {
                throw InspectionError.unexpectedFilename(
                    kind: kind,
                    filename: track.filename
                )
            }
            guard track.startOffsetMilliseconds >= 0 else {
                throw InspectionError.negativeOffset(
                    kind: kind,
                    milliseconds: track.startOffsetMilliseconds
                )
            }

            let audioURL = sessionDirectory.appendingPathComponent(track.filename)
            guard FileManager.default.fileExists(atPath: audioURL.path) else {
                throw InspectionError.missingOrEmptyFile(track.filename)
            }
            let attributes = try FileManager.default.attributesOfItem(atPath: audioURL.path)
            let byteCount = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
            guard byteCount > 0 else {
                throw InspectionError.missingOrEmptyFile(track.filename)
            }
            let audioFile: AVAudioFile
            do {
                audioFile = try AVAudioFile(forReading: audioURL)
            } catch {
                throw InspectionError.unreadableAudio(track.filename)
            }
            let sampleRate = audioFile.processingFormat.sampleRate
            guard audioFile.length > 0, sampleRate > 0 else {
                throw InspectionError.unreadableAudio(track.filename)
            }

            return AudioTrackInspection(
                kind: kind,
                filename: track.filename,
                byteCount: byteCount,
                durationSeconds: Double(audioFile.length) / sampleRate,
                startOffsetMilliseconds: track.startOffsetMilliseconds
            )
        }

        return AudioSessionInspection(
            startedAt: manifest.startedAt,
            endedAt: endedAt,
            tracks: inspections
        )
    }
}

struct InspectSession: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "inspect-session",
        abstract: "Validate a finalized local audio recording session."
    )

    @Argument(help: "Path to a recording session directory.")
    var directory: String

    func run() throws {
        let inspection = try AudioSessionInspector.inspect(
            sessionDirectory: URL(fileURLWithPath: directory, isDirectory: true)
        )
        for track in inspection.tracks {
            print(
                "✓ \(track.kind.rawValue): \(track.byteCount) bytes; "
                    + String(
                        format: "%.3f sec; offset %d ms", track.durationSeconds,
                        track.startOffsetMilliseconds)
            )
        }
        let formatter = ISO8601DateFormatter()
        print(
            "✓ finalized session: \(formatter.string(from: inspection.startedAt))"
                + " → \(formatter.string(from: inspection.endedAt))"
        )
        print("Listen to each CAF file to confirm channel separation and non-silent content.")
    }
}
