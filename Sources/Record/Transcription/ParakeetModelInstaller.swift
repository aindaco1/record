import FluidAudio
import Foundation
import RecordCore
import RecordSpeech

enum ParakeetModelInstaller {
    enum InstallResult: Equatable, Sendable {
        case alreadyInstalled
        case installed
    }

    enum InstallerError: Error, LocalizedError, CustomStringConvertible {
        case modelDirectoryNotFound
        case insufficientDiskSpace(required: Int64, available: Int64)
        case downloadFileCreationFailed
        case archiveExtractionFailed(String)

        var description: String {
            switch self {
            case .modelDirectoryNotFound:
                "The selected folder does not contain the pinned Parakeet v3 model."
            case .insufficientDiskSpace(let required, let available):
                "Installing the model needs \(required) bytes, but only \(available) are available."
            case .downloadFileCreationFailed:
                "Record couldn’t create a private temporary file for the model download."
            case .archiveExtractionFailed(let detail):
                "Record couldn’t expand the verified model archive. \(detail)"
            }
        }

        var errorDescription: String? { description }
    }

    static let verifiedSource = URL(
        string:
            "https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml/tree/\(ParakeetModelManifest.v3.sourceRevision)"
    )!
    static let downloadGuide = URL(
        string: "https://github.com/aindaco1/record/blob/main/docs/models/parakeet.md"
    )!

    static func cacheDirectory(for model: ParakeetModelID) -> URL {
        let version: AsrModelVersion = model == .v2 ? .v2 : .v3
        return AsrModels.defaultCacheDirectory(for: version)
    }

    static func isInstalled(_ model: ParakeetModelID) -> Bool {
        let version: AsrModelVersion = model == .v2 ? .v2 : .v3
        return AsrModels.modelsExist(at: cacheDirectory(for: model), version: version)
    }

    static func installV3(
        from selectedDirectory: URL,
        destination: URL = cacheDirectory(for: .v3),
        fileManager: FileManager = .default
    ) throws -> InstallResult {
        try install(
            from: selectedDirectory,
            destination: destination,
            manifest: .v3,
            fileManager: fileManager
        )
    }

    static func downloadAndInstallV3(
        downloader: any ParakeetModelArchiveDownloading =
            XPCParakeetModelArchiveDownloader(),
        destination: URL = cacheDirectory(for: .v3),
        fileManager: FileManager = .default
    ) async throws -> InstallResult {
        let descriptor = ParakeetModelDownloadDescriptor.v3
        let temporaryRoot = fileManager.temporaryDirectory.appendingPathComponent(
            "Record-Parakeet-Setup-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: temporaryRoot,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        defer { try? fileManager.removeItem(at: temporaryRoot) }

        let requiredCapacity = descriptor.byteCount + (ParakeetModelManifest.v3.byteCount * 3)
        let available = try temporaryRoot.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        ).volumeAvailableCapacityForImportantUsage
        if let available, available < requiredCapacity {
            throw InstallerError.insufficientDiskSpace(
                required: requiredCapacity,
                available: available
            )
        }

        let archive = temporaryRoot.appendingPathComponent(descriptor.assetName)
        guard
            fileManager.createFile(
                atPath: archive.path,
                contents: nil,
                attributes: [.posixPermissions: 0o600]
            )
        else {
            throw InstallerError.downloadFileCreationFailed
        }
        let outputFile = try FileHandle(forWritingTo: archive)
        do {
            try await downloader.downloadV3Archive(to: outputFile)
            try outputFile.close()
        } catch {
            try? outputFile.close()
            throw error
        }

        return try installArchive(
            from: archive,
            descriptor: descriptor,
            destination: destination,
            manifest: .v3,
            fileManager: fileManager,
            extract: ParakeetModelArchiveExtractor.extract
        )
    }

    static func installArchive(
        from archive: URL,
        descriptor: ParakeetModelDownloadDescriptor,
        destination: URL,
        manifest: ParakeetModelManifest,
        fileManager: FileManager = .default,
        extract: (URL, URL) throws -> Void
    ) throws -> InstallResult {
        try ParakeetModelDownloadVerifier.validate(
            fileAt: archive,
            descriptor: descriptor
        )
        let extractionRoot = archive.deletingLastPathComponent().appendingPathComponent(
            "expanded-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: extractionRoot,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        defer { try? fileManager.removeItem(at: extractionRoot) }
        try extract(archive, extractionRoot)
        return try install(
            from: extractionRoot,
            destination: destination,
            manifest: manifest,
            fileManager: fileManager
        )
    }

    static func install(
        from selectedDirectory: URL,
        destination: URL,
        manifest: ParakeetModelManifest,
        fileManager: FileManager = .default
    ) throws -> InstallResult {
        if (try? validate(modelAt: destination, manifest: manifest)) != nil {
            return .alreadyInstalled
        }

        let source = try findModelRoot(
            in: selectedDirectory,
            manifest: manifest,
            fileManager: fileManager
        )
        try validate(modelAt: source, manifest: manifest)

        let parent = destination.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        let available = try parent.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        ).volumeAvailableCapacityForImportantUsage
        if let available, available < manifest.byteCount {
            throw InstallerError.insufficientDiskSpace(
                required: manifest.byteCount,
                available: available
            )
        }

        let staging = parent.appendingPathComponent(
            ".record-parakeet-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? fileManager.removeItem(at: staging) }
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: false)

        for file in manifest.files {
            let input = source.appendingPathComponent(file.path)
            let output = staging.appendingPathComponent(file.path)
            try fileManager.createDirectory(
                at: output.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileManager.copyItem(at: input, to: output)
        }
        try validate(modelAt: staging, manifest: manifest)

        let backup = parent.appendingPathComponent(
            ".record-parakeet-backup-\(UUID().uuidString)",
            isDirectory: true
        )
        let hadDestination = fileManager.fileExists(atPath: destination.path)
        if hadDestination {
            try fileManager.moveItem(at: destination, to: backup)
        }
        do {
            try fileManager.moveItem(at: staging, to: destination)
        } catch {
            if hadDestination, !fileManager.fileExists(atPath: destination.path) {
                try? fileManager.moveItem(at: backup, to: destination)
            }
            throw error
        }
        try? fileManager.removeItem(at: backup)
        return .installed
    }

    static func validate(
        modelAt root: URL,
        manifest: ParakeetModelManifest
    ) throws {
        try ParakeetModelVerifier.validate(modelAt: root, manifest: manifest)
    }

    private static func findModelRoot(
        in selectedDirectory: URL,
        manifest: ParakeetModelManifest,
        fileManager: FileManager
    ) throws -> URL {
        let candidates = [
            selectedDirectory,
            selectedDirectory.appendingPathComponent(manifest.localFolderName, isDirectory: true),
            selectedDirectory.appendingPathComponent(manifest.model.rawValue, isDirectory: true),
        ]
        guard
            let root = candidates.first(where: { candidate in
                guard let first = manifest.files.first else { return false }
                return fileManager.fileExists(
                    atPath: candidate.appendingPathComponent(first.path).path
                )
            })
        else {
            throw InstallerError.modelDirectoryNotFound
        }
        return root
    }

}
