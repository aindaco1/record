import Foundation
import RecordCore

/// Finds finished Record sessions without persisting a separate history index.
/// The session manifest remains the source of truth, and only direct,
/// non-symlink children of explicitly approved roots are considered.
enum RecentRecordingLocator {
    struct Snapshot: Equatable, Sendable {
        let recordingDirectory: URL?
        let videoURL: URL?
    }

    private struct Candidate: Equatable {
        let directory: URL
        let finishedAt: Date
        let videoURL: URL?
    }

    static func snapshot(
        under roots: [URL],
        fileManager: FileManager = .default
    ) -> Snapshot {
        let allCandidates = roots.flatMap {
            candidates(under: $0, fileManager: fileManager)
        }
        let mostRecentRecording = allCandidates.max(by: isOlder)
        let mostRecentVideo =
            allCandidates
            .filter { $0.videoURL != nil }
            .max(by: isOlder)
        return Snapshot(
            recordingDirectory: mostRecentRecording?.directory,
            videoURL: mostRecentVideo?.videoURL
        )
    }

    static func mostRecent(
        under roots: [URL],
        fileManager: FileManager = .default
    ) -> URL? {
        snapshot(under: roots, fileManager: fileManager).recordingDirectory
    }

    static func isFinishedSession(
        _ directory: URL,
        under roots: [URL],
        fileManager: FileManager = .default
    ) -> Bool {
        roots.contains { root in
            candidate(
                at: directory,
                under: root,
                fileManager: fileManager
            ) != nil
        }
    }

    private static func candidates(
        under root: URL,
        fileManager: FileManager
    ) -> [Candidate] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
        guard
            let entries = try? fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles]
            )
        else { return [] }

        return entries.compactMap {
            candidate(at: $0, under: root, fileManager: fileManager)
        }
    }

    private static func candidate(
        at directory: URL,
        under root: URL,
        fileManager: FileManager
    ) -> Candidate? {
        let root = root.standardizedFileURL
        let directory = directory.standardizedFileURL
        guard directory.deletingLastPathComponent() == root else { return nil }

        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey]
        guard
            let values = try? directory.resourceValues(forKeys: keys),
            values.isDirectory == true,
            values.isSymbolicLink != true,
            directory.resolvingSymlinksInPath().deletingLastPathComponent()
                == root.resolvingSymlinksInPath(),
            fileManager.fileExists(
                atPath: directory.appendingPathComponent("session.json").path
            ),
            let manifest = try? SessionManifest.read(from: directory),
            manifest.state == .finalized || manifest.state == .interrupted
        else { return nil }

        return Candidate(
            directory: directory,
            finishedAt: manifest.endedAt ?? manifest.startedAt,
            videoURL: validatedVideoURL(
                in: directory,
                manifest: manifest,
                fileManager: fileManager
            )
        )
    }

    private static func validatedVideoURL(
        in directory: URL,
        manifest: SessionManifest,
        fileManager: FileManager
    ) -> URL? {
        let screenTracks = manifest.tracks.filter { $0.kind == .screen }
        guard screenTracks.count == 1 else { return nil }

        let videoURL = directory.appendingPathComponent(
            screenTracks[0].filename,
            isDirectory: false
        ).standardizedFileURL
        guard videoURL.deletingLastPathComponent() == directory,
            videoURL.pathExtension.lowercased() == "mov",
            fileManager.fileExists(atPath: videoURL.path),
            LocalFilePolicy.isNonemptyRegularFile(videoURL)
        else { return nil }
        return videoURL
    }

    private static func isOlder(_ lhs: Candidate, _ rhs: Candidate) -> Bool {
        if lhs.finishedAt != rhs.finishedAt {
            return lhs.finishedAt < rhs.finishedAt
        }
        return lhs.directory.lastPathComponent < rhs.directory.lastPathComponent
    }
}

/// Detects private sessions that still need recovery or manual inspection.
/// The private recordings root is the only authority: exported sessions live
/// elsewhere, and unrelated or symlinked directories never make this action
/// appear in the menu.
enum RecoveryMaterialLocator {
    static func hasMaterial(
        under root: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        let root = root.standardizedFileURL
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey]
        guard
            let entries = try? fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles]
            )
        else { return false }

        return entries.contains { entry in
            let entry = entry.standardizedFileURL
            guard entry.deletingLastPathComponent() == root,
                let values = try? entry.resourceValues(forKeys: keys),
                values.isDirectory == true,
                values.isSymbolicLink != true,
                entry.resolvingSymlinksInPath().deletingLastPathComponent()
                    == root.resolvingSymlinksInPath()
            else { return false }
            let manifest = entry.appendingPathComponent("session.json")
            let manifestKeys: Set<URLResourceKey> = [
                .isRegularFileKey, .isSymbolicLinkKey,
            ]
            guard
                let manifestValues = try? manifest.resourceValues(
                    forKeys: manifestKeys
                )
            else { return false }
            return manifestValues.isRegularFile == true
                && manifestValues.isSymbolicLink != true
        }
    }
}
