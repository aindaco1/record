import Darwin
import Foundation

/// Recovers sessions whose process exited before clean finalization. It never
/// deletes or truncates media. With a caller-supplied inspector it promotes
/// playable hidden writer artifacts and moves invalid ones into a visible
/// quarantine directory for manual review.
public enum SessionRecovery {
    public enum MediaInspection: Equatable, Sendable {
        case playable
        case empty
        case corrupt
    }

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
        public var promotedMedia: [URL]
        public var quarantinedMedia: [URL]
        public var corruptMedia: [URL]
        public var errors: [Failure]

        public init(
            interrupted: [URL] = [],
            failed: [URL] = [],
            promotedMedia: [URL] = [],
            quarantinedMedia: [URL] = [],
            corruptMedia: [URL] = [],
            errors: [Failure] = []
        ) {
            self.interrupted = interrupted
            self.failed = failed
            self.promotedMedia = promotedMedia
            self.quarantinedMedia = quarantinedMedia
            self.corruptMedia = corruptMedia
            self.errors = errors
        }
    }

    /// Atomically transitions stale `.recording` manifests based on whether
    /// any declared track contains preserved bytes. Repeated scans are
    /// idempotent. Partial-artifact recovery is opt-in because format parsing
    /// belongs to the executable layer, not RecordCore.
    public static func recover(
        in root: URL,
        at recoveryTime: Date = Date(),
        fileManager: FileManager = .default,
        isProcessRunning: ((Int32) -> Bool)? = nil,
        inspectMedia: ((URL) throws -> MediaInspection)? = nil,
        recoverPartialMedia: Bool = false
    ) -> Report {
        var report = Report()
        let processChecker = isProcessRunning ?? processIsRunning
        let resourceKeys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey]
        let directories: [URL]
        do {
            directories = try fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: Array(resourceKeys),
                options: [.skipsHiddenFiles]
            ).filter { url in
                guard let values = try? url.resourceValues(forKeys: resourceKeys) else {
                    return false
                }
                return values.isDirectory == true && values.isSymbolicLink != true
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

                if recoverPartialMedia, let inspectMedia {
                    recoverPartialArtifacts(
                        in: directory,
                        fileManager: fileManager,
                        inspectMedia: inspectMedia,
                        report: &report
                    )
                }

                let recoverableTracks =
                    manifest.tracks
                    + (manifest.captureSegments ?? []).flatMap(\.tracks)
                let hasPreservedMedia = recoverableTracks.contains { track in
                    let mediaURL = directory.appendingPathComponent(track.filename)
                    guard let attributes = try? fileManager.attributesOfItem(atPath: mediaURL.path),
                        let size = attributes[.size] as? NSNumber,
                        size.int64Value > 0
                    else { return false }
                    guard let inspectMedia else { return true }
                    do {
                        switch try inspectMedia(mediaURL) {
                        case .playable:
                            return true
                        case .corrupt:
                            report.corruptMedia.append(mediaURL)
                            // Nonempty corrupt containers can still hold bytes
                            // repair tools may recover, so never label them empty.
                            return true
                        case .empty:
                            return false
                        }
                    } catch {
                        report.errors.append(
                            Failure(directory: directory, description: String(describing: error))
                        )
                        return true
                    }
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

    private static func recoverPartialArtifacts(
        in directory: URL,
        fileManager: FileManager,
        inspectMedia: (URL) throws -> MediaInspection,
        report: inout Report
    ) {
        let candidates: [URL]
        do {
            candidates = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
                options: []
            ).filter { url in
                guard partialTarget(for: url) != nil,
                    let values = try? url.resourceValues(
                        forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
                    )
                else { return false }
                return values.isRegularFile == true && values.isSymbolicLink != true
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        } catch {
            report.errors.append(
                Failure(directory: directory, description: String(describing: error))
            )
            return
        }

        for candidate in candidates {
            do {
                let inspection = try inspectMedia(candidate)
                guard let targetName = partialTarget(for: candidate) else { continue }
                let target = directory.appendingPathComponent(targetName)
                switch inspection {
                case .playable where !fileManager.fileExists(atPath: target.path):
                    try fileManager.moveItem(at: candidate, to: target)
                    report.promotedMedia.append(target)
                case .playable:
                    let recovered = try quarantineDestination(
                        for: candidate,
                        category: "Recovered Media",
                        fileManager: fileManager
                    )
                    try fileManager.moveItem(at: candidate, to: recovered)
                    report.quarantinedMedia.append(recovered)
                case .empty, .corrupt:
                    let quarantined = try quarantineDestination(
                        for: candidate,
                        category: "Corrupt Media",
                        fileManager: fileManager
                    )
                    try fileManager.moveItem(at: candidate, to: quarantined)
                    report.quarantinedMedia.append(quarantined)
                    if inspection == .corrupt { report.corruptMedia.append(quarantined) }
                }
            } catch {
                report.errors.append(
                    Failure(directory: directory, description: String(describing: error))
                )
            }
        }
    }

    /// `.mic.<UUID>.partial.caf` becomes `mic.caf`. Requiring the UUID and a
    /// known extension prevents unrelated hidden files from being moved.
    private static func partialTarget(for url: URL) -> String? {
        let components = url.lastPathComponent.split(
            separator: ".",
            omittingEmptySubsequences: false
        )
        guard components.count >= 5,
            components[0].isEmpty,
            components[components.count - 2] == "partial",
            UUID(uuidString: String(components[components.count - 3])) != nil
        else { return nil }
        let pathExtension = String(components.last!).lowercased()
        guard pathExtension == "caf" || pathExtension == "mov" else { return nil }
        let base = components[1..<(components.count - 3)].joined(separator: ".")
        let target = "\(base).\(pathExtension)"
        guard SessionPathPolicy.isSafeRelativeFilename(target) else { return nil }
        return target
    }

    private static func quarantineDestination(
        for candidate: URL,
        category: String,
        fileManager: FileManager
    ) throws -> URL {
        let recovery = candidate.deletingLastPathComponent()
            .appendingPathComponent("Recovery", isDirectory: true)
            .appendingPathComponent(category, isDirectory: true)
        try fileManager.createDirectory(at: recovery, withIntermediateDirectories: true)
        return recovery.appendingPathComponent(
            String(candidate.lastPathComponent.drop(while: { $0 == "." }))
        )
    }
}
