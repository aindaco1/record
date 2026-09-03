import CryptoKit
import Foundation

public struct ParakeetModelDownloadDescriptor: Equatable, Sendable {
    public let assetName: String
    public let downloadURLString: String
    public let byteCount: Int64
    public let sha256: String

    public init(
        assetName: String,
        downloadURLString: String,
        byteCount: Int64,
        sha256: String
    ) {
        self.assetName = assetName
        self.downloadURLString = downloadURLString
        self.byteCount = byteCount
        self.sha256 = sha256
    }

    public static let v3 = ParakeetModelDownloadDescriptor(
        assetName: "Record-Parakeet-v3-aed0274.zip",
        downloadURLString:
            "https://github.com/aindaco1/record/releases/download/v1.3.0/Record-Parakeet-v3-aed0274.zip",
        byteCount: 465_779_146,
        sha256: "c9089c5535e5518ec5f4e53074f120d4ce2675841bb0bacd541499f22b94fc9c"
    )

    public func allowsDownloadURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else {
            return false
        }
        return host == "github.com" || host.hasSuffix(".githubusercontent.com")
    }
}

public enum ParakeetModelDownloadVerificationError: Error, LocalizedError,
    CustomStringConvertible
{
    case unsafeFile
    case unexpectedSize(expected: Int64, actual: Int64)
    case checksumMismatch

    public var description: String {
        switch self {
        case .unsafeFile:
            "The downloaded model archive is not a safe regular file."
        case .unexpectedSize(let expected, let actual):
            "The model download has size \(actual), expected \(expected)."
        case .checksumMismatch:
            "The downloaded model archive failed SHA-256 verification."
        }
    }

    public var errorDescription: String? { description }
}

public enum ParakeetModelDownloadVerifier {
    public static func validate(
        fileAt url: URL,
        descriptor: ParakeetModelDownloadDescriptor = .v3
    ) throws {
        let values = try url.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        )
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw ParakeetModelDownloadVerificationError.unsafeFile
        }
        let byteCount = Int64(values.fileSize ?? -1)
        guard byteCount == descriptor.byteCount else {
            throw ParakeetModelDownloadVerificationError.unexpectedSize(
                expected: descriptor.byteCount,
                actual: byteCount
            )
        }
        guard try sha256(of: url) == descriptor.sha256 else {
            throw ParakeetModelDownloadVerificationError.checksumMismatch
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

@objc public protocol ParakeetModelDownloaderXPCProtocol {
    func downloadParakeetV3(
        to outputFile: FileHandle,
        withReply reply: @escaping (NSError?) -> Void
    )
    func cancelDownload()
}
