import Foundation
import RecordCore

/// Finds finished Record sessions without persisting a separate history index.
/// The session manifest remains the source of truth, and only direct,
/// non-symlink children of explicitly approved roots are considered.
enum RecentRecordingLocator {
    struct Candidate: Equatable {
        let directory: URL
        let finishedAt: Date
    }

    static func mostRecent(
        under roots: [URL],
        fileManager: FileManager = .default
    ) -> URL? {
        roots.compactMap { root in
            candidates(under: root, fileManager: fileManager).max(by: isOlder)
        }
        .max(by: isOlder)?
        .directory
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
            finishedAt: manifest.endedAt ?? manifest.startedAt
        )
    }

    private static func isOlder(_ lhs: Candidate, _ rhs: Candidate) -> Bool {
        if lhs.finishedAt != rhs.finishedAt {
            return lhs.finishedAt < rhs.finishedAt
        }
        return lhs.directory.lastPathComponent < rhs.directory.lastPathComponent
    }
}
