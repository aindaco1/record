import Foundation
@testable import Record
import XCTest

final class GifskiHandoffTests: XCTestCase {
    func testAcceptsOnlyNonemptyLocalMovies() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "record-gifski-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let movie = root.appendingPathComponent("recording.mov")
        try Data("movie".utf8).write(to: movie)

        XCTAssertNoThrow(try GifskiHandoff.validate(videoURL: movie))
        XCTAssertThrowsError(
            try GifskiHandoff.validate(videoURL: root.appendingPathComponent("missing.mov"))
        ) { error in
            XCTAssertEqual(error as? GifskiHandoff.HandoffError, .invalidVideo)
        }
        XCTAssertThrowsError(
            try GifskiHandoff.validate(videoURL: root.appendingPathComponent("recording.mp4"))
        )

        let empty = root.appendingPathComponent("empty.mov")
        XCTAssertTrue(FileManager.default.createFile(atPath: empty.path, contents: Data()))
        XCTAssertThrowsError(try GifskiHandoff.validate(videoURL: empty))

        let link = root.appendingPathComponent("linked.mov")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: movie)
        XCTAssertThrowsError(try GifskiHandoff.validate(videoURL: link))
        XCTAssertThrowsError(try GifskiHandoff.validate(videoURL: root))
    }
}
