import CryptoKit
import FluidAudio
import Foundation
import RecordCore

struct ParakeetModelManifest: Sendable {
    struct FileSpec: Sendable {
        let path: String
        let size: Int64
        let sha256: String
    }

    let model: ParakeetModelID
    let sourceRevision: String
    let localFolderName: String
    let files: [FileSpec]

    var byteCount: Int64 { files.reduce(0) { $0 + $1.size } }

    static let v3 = ParakeetModelManifest(
        model: .v3,
        sourceRevision: "aed02740059203c4a87495924f685de3722ae9ce",
        localFolderName: "parakeet-tdt-0.6b-v3",
        files: [
            .init(
                path: "Preprocessor.mlmodelc/coremldata.bin", size: 486,
                sha256: "dbde3f2300842c1fd51ef3ff948a0bcffe65ffd2dca10707f2509f32c1d65b1d"),
            .init(
                path: "Preprocessor.mlmodelc/metadata.json", size: 2_841,
                sha256: "2a98699e22d279dd37fa1d238aeb1c6db1df0d6fad687775324157689d8f3acf"),
            .init(
                path: "Preprocessor.mlmodelc/model.mil", size: 28_181,
                sha256: "4b8518a956450fec57f06c2a21bdffc26973f7f1fa6842fb38fe917f896b6b93"),
            .init(
                path: "Preprocessor.mlmodelc/weights/weight.bin", size: 491_072,
                sha256: "129b76e3aeafa8afa3ea76d995b964b145fe83700d579f6ff42c4c38fa0968ea"),
            .init(
                path: "Encoder.mlmodelc/coremldata.bin", size: 485,
                sha256: "d48034a167a82e88fc3df64f60af963ab3983538271175b8319e7d5720a0fb86"),
            .init(
                path: "Encoder.mlmodelc/metadata.json", size: 2_921,
                sha256: "da24da9cca943fb29d7fa8e376d57fca7cb3aa08ca51b956b0b0e56813f087e9"),
            .init(
                path: "Encoder.mlmodelc/model.mil", size: 959_769,
                sha256: "ed7b19156ca29fa7dfd6891deb9fda4b0e8893f68597c985d135736546a43808"),
            .init(
                path: "Encoder.mlmodelc/weights/weight.bin", size: 445_187_200,
                sha256: "e2020f323703477a5b21d7c2d282c403e371afb5962e79877e3033e73ba6f421"),
            .init(
                path: "Decoder.mlmodelc/coremldata.bin", size: 554,
                sha256: "18647af085d87bd8f3121c8a9b4d4564c1ede038dab63d295b4e745cf2d7fb99"),
            .init(
                path: "Decoder.mlmodelc/metadata.json", size: 3_427,
                sha256: "a39e93cd8371b8ded92635c7804fcd0590f0d1dd9415c6d19a0484be073077d9"),
            .init(
                path: "Decoder.mlmodelc/model.mil", size: 13_110,
                sha256: "ef2a0a281695398a62fde86ac269c68f73d5b578d7ed3b31f2ba91a2d1ea1f35"),
            .init(
                path: "Decoder.mlmodelc/weights/weight.bin", size: 23_604_992,
                sha256: "48adf0f0d47c406c8253d4f7fef967436a39da14f5a65e66d5a4b407be355d41"),
            .init(
                path: "JointDecisionv3.mlmodelc/coremldata.bin", size: 521,
                sha256: "f5fc08b741400f0088492c9e839418b1e18522f19cba28d361dd030c5f398342"),
            .init(
                path: "JointDecisionv3.mlmodelc/metadata.json", size: 3_453,
                sha256: "d9307211b9a37e0f0ac260c7660b1571a3de25841035cfdf9b58fd40425f890f"),
            .init(
                path: "JointDecisionv3.mlmodelc/model.mil", size: 11_775,
                sha256: "be60732943389a047175111a83f8839f3eb39d4803adafa828a0871b2f39818d"),
            .init(
                path: "JointDecisionv3.mlmodelc/weights/weight.bin", size: 12_642_764,
                sha256: "4e0e63d840032f7f07ddb1d64446051166281e5491bf22da8a945c41f6eedb3e"),
            .init(
                path: "parakeet_vocab.json", size: 151_122,
                sha256: "7ec60e05f1b24480736ec0eed40900f4626bce1fa9a60fd700ec7e2a59198735"),
        ]
    )
}

enum ParakeetModelInstaller {
    enum InstallResult: Equatable, Sendable {
        case alreadyInstalled
        case installed
    }

    enum InstallerError: Error, CustomStringConvertible {
        case modelDirectoryNotFound
        case unsafeFile(String)
        case missingFile(String)
        case unexpectedSize(path: String, expected: Int64, actual: Int64)
        case checksumMismatch(String)
        case insufficientDiskSpace(required: Int64, available: Int64)

        var description: String {
            switch self {
            case .modelDirectoryNotFound:
                "The selected folder does not contain the pinned Parakeet v3 model."
            case .unsafeFile(let path):
                "The model contains an unsafe symbolic link: \(path)"
            case .missingFile(let path):
                "The model is incomplete; \(path) is missing."
            case .unexpectedSize(let path, let expected, let actual):
                "The model file \(path) has size \(actual), expected \(expected)."
            case .checksumMismatch(let path):
                "The model file \(path) failed SHA-256 verification."
            case .insufficientDiskSpace(let required, let available):
                "Installing the model needs \(required) bytes, but only \(available) are available."
            }
        }
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
        let resolvedRoot = root.resolvingSymlinksInPath().standardizedFileURL
        for file in manifest.files {
            let candidate = root.appendingPathComponent(file.path)
            let resolved = candidate.resolvingSymlinksInPath().standardizedFileURL
            guard resolved.path.hasPrefix(resolvedRoot.path + "/") else {
                throw InstallerError.unsafeFile(file.path)
            }
            let values: URLResourceValues
            do {
                values = try candidate.resourceValues(
                    forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
                )
            } catch {
                throw InstallerError.missingFile(file.path)
            }
            guard values.isSymbolicLink != true, values.isRegularFile == true else {
                throw InstallerError.unsafeFile(file.path)
            }
            let size = Int64(values.fileSize ?? -1)
            guard size == file.size else {
                throw InstallerError.unexpectedSize(
                    path: file.path,
                    expected: file.size,
                    actual: size
                )
            }
            guard try sha256(of: candidate) == file.sha256 else {
                throw InstallerError.checksumMismatch(file.path)
            }
        }
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

    private static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
