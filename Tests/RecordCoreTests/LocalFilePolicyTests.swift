import Foundation
@testable import RecordCore
import XCTest

final class LocalFilePolicyTests: XCTestCase {
    func testReturnsSizesOnlyForRealNonsymlinkFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "record-local-file-policy-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let empty = root.appendingPathComponent("empty")
        let nonempty = root.appendingPathComponent("nonempty")
        let link = root.appendingPathComponent("link")
        XCTAssertTrue(FileManager.default.createFile(atPath: empty.path, contents: Data()))
        try Data([1, 2, 3]).write(to: nonempty)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: nonempty)

        XCTAssertEqual(LocalFilePolicy.regularFileSize(at: empty), 0)
        XCTAssertEqual(LocalFilePolicy.regularFileSize(at: nonempty), 3)
        XCTAssertNil(LocalFilePolicy.regularFileSize(at: link))
        XCTAssertNil(LocalFilePolicy.regularFileSize(at: root))
        XCTAssertNil(LocalFilePolicy.regularFileSize(at: URL(string: "https://example.com")!))
        XCTAssertFalse(LocalFilePolicy.isNonemptyRegularFile(empty))
        XCTAssertTrue(LocalFilePolicy.isNonemptyRegularFile(nonempty))
    }
}
