import CryptoKit
import Foundation
@testable import RecordCore
import XCTest

final class ParakeetModelDownloadContractTests: XCTestCase {
    func testV3DescriptorPinsImmutableGitHubAsset() {
        let descriptor = ParakeetModelDownloadDescriptor.v3

        XCTAssertEqual(descriptor.assetName, "Record-Parakeet-v3-aed0274.zip")
        XCTAssertEqual(descriptor.byteCount, 465_779_146)
        XCTAssertEqual(
            descriptor.sha256,
            "c9089c5535e5518ec5f4e53074f120d4ce2675841bb0bacd541499f22b94fc9c"
        )
        XCTAssertEqual(
            descriptor.downloadURLString,
            "https://github.com/aindaco1/record/releases/download/v1.3.0/Record-Parakeet-v3-aed0274.zip"
        )
    }

    func testDownloadURLPolicyAllowsOnlyGitHubHTTPSHosts() throws {
        let descriptor = ParakeetModelDownloadDescriptor.v3

        XCTAssertTrue(
            descriptor.allowsDownloadURL(
                try XCTUnwrap(URL(string: descriptor.downloadURLString))
            )
        )
        XCTAssertTrue(
            descriptor.allowsDownloadURL(
                try XCTUnwrap(URL(string: "https://release-assets.githubusercontent.com/file"))
            )
        )
        XCTAssertFalse(
            descriptor.allowsDownloadURL(
                try XCTUnwrap(URL(string: "http://github.com/aindaco1/record"))
            )
        )
        XCTAssertFalse(
            descriptor.allowsDownloadURL(
                try XCTUnwrap(URL(string: "https://github.com.example.invalid/model"))
            )
        )
    }

    func testArchiveVerifierRejectsWrongSizeAndChecksum() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "record-download-contract-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let archive = root.appendingPathComponent("model.zip")
        try Data("model".utf8).write(to: archive)
        let valid = ParakeetModelDownloadDescriptor(
            assetName: "model.zip",
            downloadURLString: "https://github.com/example/model.zip",
            byteCount: 5,
            sha256: SHA256.hash(data: Data("model".utf8))
                .map { String(format: "%02x", $0) }
                .joined()
        )

        XCTAssertNoThrow(
            try ParakeetModelDownloadVerifier.validate(fileAt: archive, descriptor: valid)
        )
        XCTAssertThrowsError(
            try ParakeetModelDownloadVerifier.validate(
                fileAt: archive,
                descriptor: .init(
                    assetName: "model.zip",
                    downloadURLString: valid.downloadURLString,
                    byteCount: 6,
                    sha256: valid.sha256
                )
            )
        )
        XCTAssertThrowsError(
            try ParakeetModelDownloadVerifier.validate(
                fileAt: archive,
                descriptor: .init(
                    assetName: "model.zip",
                    downloadURLString: valid.downloadURLString,
                    byteCount: 5,
                    sha256: String(repeating: "0", count: 64)
                )
            )
        )
    }
}
