import CryptoKit
import Foundation
@testable import Record
import RecordCore
import RecordSpeech
import XCTest

final class ParakeetModelInstallerTests: XCTestCase {
    func testVerifiedModelInstallsAtomically() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try write("alpha", to: fixture.source.appendingPathComponent("A/model.bin"))
        try write("beta", to: fixture.source.appendingPathComponent("vocab.json"))

        XCTAssertEqual(
            try ParakeetModelInstaller.install(
                from: fixture.source,
                destination: fixture.destination,
                manifest: fixture.manifest
            ),
            .installed
        )
        XCTAssertEqual(
            try String(
                contentsOf: fixture.destination.appendingPathComponent("A/model.bin"),
                encoding: .utf8
            ),
            "alpha"
        )
        try ParakeetModelInstaller.validate(
            modelAt: fixture.destination,
            manifest: fixture.manifest
        )
    }

    func testCorruptImportCannotReplaceExistingModel() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try write("old", to: fixture.destination.appendingPathComponent("sentinel"))
        try write("wrong", to: fixture.source.appendingPathComponent("A/model.bin"))
        try write("beta", to: fixture.source.appendingPathComponent("vocab.json"))

        XCTAssertThrowsError(
            try ParakeetModelInstaller.install(
                from: fixture.source,
                destination: fixture.destination,
                manifest: fixture.manifest
            )
        )
        XCTAssertEqual(
            try String(
                contentsOf: fixture.destination.appendingPathComponent("sentinel"),
                encoding: .utf8
            ),
            "old"
        )
    }

    func testIncompleteDownloadIsRejectedBeforeInstallation() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try write("alpha", to: fixture.source.appendingPathComponent("A/model.bin"))

        XCTAssertThrowsError(
            try ParakeetModelInstaller.install(
                from: fixture.source,
                destination: fixture.destination,
                manifest: fixture.manifest
            )
        ) { error in
            XCTAssertTrue(String(describing: error).contains("vocab.json is missing"))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.destination.path))
    }

    func testSymbolicLinkCannotEscapeSelectedDirectory() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let outside = fixture.root.appendingPathComponent("outside")
        try write("alpha", to: outside.appendingPathComponent("model.bin"))
        try FileManager.default.createDirectory(
            at: fixture.source.appendingPathComponent("A"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(
            at: fixture.source.appendingPathComponent("A/model.bin"),
            withDestinationURL: outside.appendingPathComponent("model.bin")
        )
        try write("beta", to: fixture.source.appendingPathComponent("vocab.json"))

        XCTAssertThrowsError(
            try ParakeetModelInstaller.install(
                from: fixture.source,
                destination: fixture.destination,
                manifest: fixture.manifest
            )
        ) { error in
            XCTAssertTrue(String(describing: error).contains("unsafe symbolic link"))
        }
    }

    func testVerifiedArchiveUsesExistingAtomicInstaller() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let archive = fixture.root.appendingPathComponent("model.zip")
        try write("archive", to: archive)
        let descriptor = ParakeetModelDownloadDescriptor(
            assetName: "model.zip",
            downloadURLString: "https://github.com/example/model.zip",
            byteCount: 7,
            sha256: digest("archive")
        )

        XCTAssertEqual(
            try ParakeetModelInstaller.installArchive(
                from: archive,
                descriptor: descriptor,
                destination: fixture.destination,
                manifest: fixture.manifest
            ) { _, extractionRoot in
                let model = extractionRoot.appendingPathComponent("model", isDirectory: true)
                try self.write("alpha", to: model.appendingPathComponent("A/model.bin"))
                try self.write("beta", to: model.appendingPathComponent("vocab.json"))
            },
            .installed
        )
        try ParakeetModelInstaller.validate(
            modelAt: fixture.destination,
            manifest: fixture.manifest
        )
    }

    func testVerifiedArchiveFindsModelInsidePublishedDistributionWrapper() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let archive = fixture.root.appendingPathComponent(
            "Record-Parakeet-v3-aed0274.zip"
        )
        try write("archive", to: archive)
        let descriptor = ParakeetModelDownloadDescriptor(
            assetName: archive.lastPathComponent,
            downloadURLString: "https://github.com/example/model.zip",
            byteCount: 7,
            sha256: digest("archive")
        )

        XCTAssertEqual(
            try ParakeetModelInstaller.installArchive(
                from: archive,
                descriptor: descriptor,
                destination: fixture.destination,
                manifest: fixture.manifest
            ) { _, extractionRoot in
                let wrapper = extractionRoot.appendingPathComponent(
                    "Record-Parakeet-v3-aed0274",
                    isDirectory: true
                )
                try self.write(
                    "license",
                    to: wrapper.appendingPathComponent("LICENSE.txt")
                )
                let model = wrapper.appendingPathComponent("model", isDirectory: true)
                try self.write("alpha", to: model.appendingPathComponent("A/model.bin"))
                try self.write("beta", to: model.appendingPathComponent("vocab.json"))
            },
            .installed
        )
        try ParakeetModelInstaller.validate(
            modelAt: fixture.destination,
            manifest: fixture.manifest
        )
    }

    func testCorruptArchiveIsRejectedBeforeExtraction() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let archive = fixture.root.appendingPathComponent("model.zip")
        try write("corrupt", to: archive)
        var extracted = false

        XCTAssertThrowsError(
            try ParakeetModelInstaller.installArchive(
                from: archive,
                descriptor: .init(
                    assetName: "model.zip",
                    downloadURLString: "https://github.com/example/model.zip",
                    byteCount: 7,
                    sha256: String(repeating: "0", count: 64)
                ),
                destination: fixture.destination,
                manifest: fixture.manifest
            ) { _, _ in
                extracted = true
            }
        )
        XCTAssertFalse(extracted)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.destination.path))
    }

    private func makeFixture() throws -> (
        root: URL,
        source: URL,
        destination: URL,
        manifest: ParakeetModelManifest
    ) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "record-model-installer-\(UUID().uuidString)",
            isDirectory: true
        )
        let source = root.appendingPathComponent("download", isDirectory: true)
        let destination = root.appendingPathComponent("cache/model", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let manifest = ParakeetModelManifest(
            model: .v3,
            sourceRevision: "fixture",
            localFolderName: "model",
            files: [
                .init(path: "A/model.bin", size: 5, sha256: digest("alpha")),
                .init(path: "vocab.json", size: 4, sha256: digest("beta")),
            ]
        )
        return (root, source, destination, manifest)
    }

    private func write(_ string: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(string.utf8).write(to: url)
    }

    private func digest(_ string: String) -> String {
        SHA256.hash(data: Data(string.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
