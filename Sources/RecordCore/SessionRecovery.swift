import Foundation
import Darwin

/// Recovers sessions whose process exited before a clean finalization. It does
/// not delete, truncate, rename, or rewrite media files.
public enum SessionRecovery {
    public struct Failure: Equatable, Sendable {
        public let directory: URL
        public let description: String

        public init(directory: URL, description: String) {
            self.directory = directory
            self.description = description
        }
    }

    public struct Report: Equatable, Sendable {
        public var interrupted: [URL]
        public var failed: [URL]
        public var errors: [Failure]

        public init(
            interrupted: [URL] = [],
            failed: [URL] = [],
            errors: [Failure] = []
        ) {
            self.interrupted = interrupted
            self.failed = failed
            self.errors = errors
        }
    }

    /// Atomically transitions stale `.recording` manifests based on whether
    /// any declared track contains bytes. Repeated scans are idempotent.
    public static func recover(
        in root: URL,
        at recoveryTime: Date = Date(),
        fileManager: FileManager = .default,
        isProcessRunning: ((Int32) -> Bool)? = nil
    ) -> Report {
        var report = Report()
        let processChecker = isProcessRunning ?? processIsRunning
        let resourceKeys: Set<URLResourceKey> = [.isDirectoryKey]
        let directories: [URL]
        do {
            directories = try fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: Array(resourceKeys),
                options: [.skipsHiddenFiles]
            ).filter { url in
                (try? url.resourceValues(forKeys: resourceKeys).isDirectory) == true
            }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        } catch {
            report.errors.append(Failure(directory: root, description: String(describing: error)))
            return report
        }

        for directory in directories {
            let manifestURL = directory.appendingPathComponent("session.json")
            guard fileManager.fileExists(atPath: manifestURL.path) else { continue }

            do {
                let manifest = try SessionManifest.read(from: directory)
                guard manifest.state == .recording else { continue }
                if let owner = manifest.ownerProcessIdentifier, processChecker(owner) {
                    continue
                }

                let hasPreservedMedia = manifest.tracks.contains { track in
                    let mediaURL = directory.appendingPathComponent(track.filename)
                    guard let attributes = try? fileManager.attributesOfItem(atPath: mediaURL.path),
                        let size = attributes[.size] as? NSNumber
                    else { return false }
                    return size.int64Value > 0
                }

                let transitionTime = max(recoveryTime, manifest.startedAt)
                let recovered =
                    hasPreservedMedia
                    ? try manifest.interrupted(at: transitionTime)
                    : try manifest.failed(at: transitionTime)
                try recovered.write(to: directory)
                if hasPreservedMedia {
                    report.interrupted.append(directory)
                } else {
                    report.failed.append(directory)
                }
            } catch {
                report.errors.append(
                    Failure(directory: directory, description: String(describing: error))
                )
            }
        }
        return report
    }

    private static func processIsRunning(_ processIdentifier: Int32) -> Bool {
        guard processIdentifier > 0 else { return false }
        if kill(processIdentifier, 0) == 0 { return true }
        return errno == EPERM
    }
}
