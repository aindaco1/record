import CryptoKit
import Foundation
import RecordCore

public struct ParakeetModelManifest: Sendable {
    public struct FileSpec: Sendable {
        public let path: String
        public let size: Int64
        public let sha256: String

        public init(path: String, size: Int64, sha256: String) {
            self.path = path
            self.size = size
            self.sha256 = sha256
        }
    }

    public let model: ParakeetModelID
    public let sourceRevision: String
    public let localFolderName: String
    public let files: [FileSpec]

    public var byteCount: Int64 { files.reduce(0) { $0 + $1.size } }

    public init(
        model: ParakeetModelID,
        sourceRevision: String,
        localFolderName: String,
        files: [FileSpec]
    ) {
        self.model = model
        self.sourceRevision = sourceRevision
        self.localFolderName = localFolderName
        self.files = files
    }

    public static let v3 = ParakeetModelManifest(
        model: .v3,
        sourceRevision: "aed02740059203c4a87495924f685de3722ae9ce",
        localFolderName: "parakeet-tdt-0.6b-v3",
        files: [
            .init(path: "Preprocessor.mlmodelc/coremldata.bin", size: 486, sha256: "dbde3f2300842c1fd51ef3ff948a0bcffe65ffd2dca10707f2509f32c1d65b1d"),
            .init(path: "Preprocessor.mlmodelc/metadata.json", size: 2_841, sha256: "2a98699e22d279dd37fa1d238aeb1c6db1df0d6fad687775324157689d8f3acf"),
            .init(path: "Preprocessor.mlmodelc/model.mil", size: 28_181, sha256: "4b8518a956450fec57f06c2a21bdffc26973f7f1fa6842fb38fe917f896b6b93"),
            .init(path: "Preprocessor.mlmodelc/weights/weight.bin", size: 491_072, sha256: "129b76e3aeafa8afa3ea76d995b964b145fe83700d579f6ff42c4c38fa0968ea"),
            .init(path: "Encoder.mlmodelc/coremldata.bin", size: 485, sha256: "d48034a167a82e88fc3df64f60af963ab3983538271175b8319e7d5720a0fb86"),
            .init(path: "Encoder.mlmodelc/metadata.json", size: 2_921, sha256: "da24da9cca943fb29d7fa8e376d57fca7cb3aa08ca51b956b0b0e56813f087e9"),
            .init(path: "Encoder.mlmodelc/model.mil", size: 959_769, sha256: "ed7b19156ca29fa7dfd6891deb9fda4b0e8893f68597c985d135736546a43808"),
            .init(path: "Encoder.mlmodelc/weights/weight.bin", size: 445_187_200, sha256: "e2020f323703477a5b21d7c2d282c403e371afb5962e79877e3033e73ba6f421"),
            .init(path: "Decoder.mlmodelc/coremldata.bin", size: 554, sha256: "18647af085d87bd8f3121c8a9b4d4564c1ede038dab63d295b4e745cf2d7fb99"),
            .init(path: "Decoder.mlmodelc/metadata.json", size: 3_427, sha256: "a39e93cd8371b8ded92635c7804fcd0590f0d1dd9415c6d19a0484be073077d9"),
            .init(path: "Decoder.mlmodelc/model.mil", size: 13_110, sha256: "ef2a0a281695398a62fde86ac269c68f73d5b578d7ed3b31f2ba91a2d1ea1f35"),
            .init(path: "Decoder.mlmodelc/weights/weight.bin", size: 23_604_992, sha256: "48adf0f0d47c406c8253d4f7fef967436a39da14f5a65e66d5a4b407be355d41"),
            .init(path: "JointDecisionv3.mlmodelc/coremldata.bin", size: 521, sha256: "f5fc08b741400f0088492c9e839418b1e18522f19cba28d361dd030c5f398342"),
            .init(path: "JointDecisionv3.mlmodelc/metadata.json", size: 3_453, sha256: "d9307211b9a37e0f0ac260c7660b1571a3de25841035cfdf9b58fd40425f890f"),
            .init(path: "JointDecisionv3.mlmodelc/model.mil", size: 11_775, sha256: "be60732943389a047175111a83f8839f3eb39d4803adafa828a0871b2f39818d"),
            .init(path: "JointDecisionv3.mlmodelc/weights/weight.bin", size: 12_642_764, sha256: "4e0e63d840032f7f07ddb1d64446051166281e5491bf22da8a945c41f6eedb3e"),
            .init(path: "parakeet_vocab.json", size: 151_122, sha256: "7ec60e05f1b24480736ec0eed40900f4626bce1fa9a60fd700ec7e2a59198735"),
        ]
    )
}

public enum ParakeetModelVerifier {
    public enum VerificationError: Error, CustomStringConvertible {
        case unsafeFile(String)
        case missingFile(String)
        case unexpectedSize(path: String, expected: Int64, actual: Int64)
        case checksumMismatch(String)

        public var description: String {
            switch self {
            case .unsafeFile(let path): "The model contains an unsafe symbolic link: \(path)"
            case .missingFile(let path): "The model is incomplete; \(path) is missing."
            case .unexpectedSize(let path, let expected, let actual):
                "The model file \(path) has size \(actual), expected \(expected)."
            case .checksumMismatch(let path): "The model file \(path) failed SHA-256 verification."
            }
        }
    }

    public static func validateV3(at root: URL) throws {
        try validate(modelAt: root, manifest: .v3)
    }

    public static func validate(modelAt root: URL, manifest: ParakeetModelManifest) throws {
        let resolvedRoot = root.resolvingSymlinksInPath().standardizedFileURL
        for file in manifest.files {
            let candidate = root.appendingPathComponent(file.path)
            let resolved = candidate.resolvingSymlinksInPath().standardizedFileURL
            guard resolved.path.hasPrefix(resolvedRoot.path + "/") else {
                throw VerificationError.unsafeFile(file.path)
            }
            let values: URLResourceValues
            do {
                values = try candidate.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            } catch {
                throw VerificationError.missingFile(file.path)
            }
            guard values.isSymbolicLink != true, values.isRegularFile == true else {
                throw VerificationError.unsafeFile(file.path)
            }
            let size = Int64(values.fileSize ?? -1)
            guard size == file.size else {
                throw VerificationError.unexpectedSize(path: file.path, expected: file.size, actual: size)
            }
            guard try sha256(of: candidate) == file.sha256 else {
                throw VerificationError.checksumMismatch(file.path)
            }
        }
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
