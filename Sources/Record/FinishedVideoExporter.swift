import Foundation
import RecordCore

struct FinishedSessionExport: Equatable, Sendable {
    let directoryURL: URL
    let videoURL: URL?
}

/// Copies one finalized session into a user-approved destination as a complete
/// directory. The hidden sibling is promoted with one same-volume rename, so
/// Finder never sees a half-copied recording.
enum FinishedSessionExporter {
    enum ExportError: Error, Equatable {
        case invalidSource
        case destinationUnavailable
        case invalidName
    }

    static func export(
        sourceDirectory: URL,
        to destinationRoot: URL,
        preferredDirectoryName: String,
        fileManager: FileManager = .default
    ) throws -> FinishedSessionExport {
        guard
            let manifest = try? validatedManifest(
                in: sourceDirectory,
                fileManager: fileManager
            )
        else {
            throw ExportError.invalidSource
        }
        guard isDirectory(destinationRoot, fileManager: fileManager) else {
            throw ExportError.destinationUnavailable
        }
        guard LocalFileNamePolicy.isSafeComponent(preferredDirectoryName),
            preferredDirectoryName
                == preferredDirectoryName.trimmingCharacters(
                    in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "."))
                ),
            URL(fileURLWithPath: preferredDirectoryName).lastPathComponent
                == preferredDirectoryName
        else {
            throw ExportError.invalidName
        }

        let finalURL = availableURL(
            baseName: preferredDirectoryName,
            in: destinationRoot,
            fileManager: fileManager
        )
        let partialURL = destinationRoot.appendingPathComponent(
            ".\(preferredDirectoryName).\(UUID().uuidString).partial",
            isDirectory: true
        )
        defer { try? fileManager.removeItem(at: partialURL) }

        try fileManager.createDirectory(at: partialURL, withIntermediateDirectories: false)
        try copyFile(
            named: "session.json",
            from: sourceDirectory,
            to: partialURL,
            fileManager: fileManager
        )
        for track in manifest.tracks {
            try copyFile(
                named: track.filename,
                from: sourceDirectory,
                to: partialURL,
                fileManager: fileManager
            )
        }
        _ = try validatedManifest(in: partialURL, fileManager: fileManager)
        try fileManager.moveItem(at: partialURL, to: finalURL)

        return FinishedSessionExport(
            directoryURL: finalURL,
            videoURL: manifest.tracks.first(where: { $0.kind == .screen }).map {
                finalURL.appendingPathComponent($0.filename, isDirectory: false)
            }
        )
    }

    private static func validatedManifest(
        in sourceDirectory: URL,
        fileManager: FileManager
    ) throws -> SessionManifest {
        guard isDirectory(sourceDirectory, fileManager: fileManager),
            !isSymbolicLink(sourceDirectory),
            let manifest = try? SessionManifest.read(from: sourceDirectory),
            manifest.state == .finalized,
            !manifest.tracks.isEmpty,
            manifest.tracks.filter({ $0.kind == .screen }).count <= 1
        else {
            throw ExportError.invalidSource
        }

        for filename in ["session.json"] + manifest.tracks.map(\.filename) {
            let file = sourceDirectory.appendingPathComponent(filename, isDirectory: false)
            guard isNonemptyRegularFile(file) else {
                throw ExportError.invalidSource
            }
        }
        return manifest
    }

    private static func copyFile(
        named filename: String,
        from sourceDirectory: URL,
        to destinationDirectory: URL,
        fileManager: FileManager
    ) throws {
        try fileManager.copyItem(
            at: sourceDirectory.appendingPathComponent(filename, isDirectory: false),
            to: destinationDirectory.appendingPathComponent(filename, isDirectory: false)
        )
    }

    private static func availableURL(
        baseName: String,
        in directory: URL,
        fileManager: FileManager
    ) -> URL {
        var suffix = 1
        while true {
            let name = suffix == 1 ? baseName : "\(baseName)-\(suffix)"
            let candidate = directory.appendingPathComponent(name, isDirectory: true)
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            suffix += 1
        }
    }

    private static func isDirectory(_ url: URL, fileManager: FileManager) -> Bool {
        var isDirectory = ObjCBool(false)
        return url.isFileURL
            && fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    private static func isNonemptyRegularFile(_ url: URL) -> Bool {
        guard
            let values = try? url.resourceValues(
                forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]
            )
        else { return false }
        return values.isRegularFile == true
            && values.isSymbolicLink != true
            && (values.fileSize ?? 0) > 0
    }

    private static func isSymbolicLink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }
}

/// Removes only a finalized direct child of Record's private session root.
/// Export completion and validation happen before this is called.
enum PrivateSessionCleaner {
    enum CleanupError: Error, Equatable {
        case unsafeDirectory
        case sessionNotFinalized
    }

    static func removeFinalizedSession(
        _ sessionDirectory: URL,
        under recordingsRoot: URL,
        fileManager: FileManager = .default
    ) throws {
        let root = recordingsRoot.standardizedFileURL
        let session = sessionDirectory.standardizedFileURL
        guard root.isFileURL,
            session.isFileURL,
            session != root,
            session.deletingLastPathComponent() == root,
            session.deletingLastPathComponent().resolvingSymlinksInPath()
                == root.resolvingSymlinksInPath(),
            (try? session.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink)
                != true
        else {
            throw CleanupError.unsafeDirectory
        }
        guard let manifest = try? SessionManifest.read(from: session),
            manifest.state == .finalized
        else {
            throw CleanupError.sessionNotFinalized
        }
        try fileManager.removeItem(at: session)
    }
}
