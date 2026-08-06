import Foundation
import RecordCore
import XCTest

final class TranscriptDocumentTests: XCTestCase {
    func testRenderingAndCanonicalJSONRemainInSync() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TranscriptDocumentTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let document = TranscriptDocument(
            engine: "parakeet",
            model: "local-model",
            createdAt: "2026-08-06T17:00:00Z",
            segments: [
                .init(
                    speaker: "me",
                    startMilliseconds: 3_723_000,
                    endMilliseconds: 3_724_000,
                    text: "A local transcript."
                )
            ]
        )

        try document.write(to: directory, title: "Session")

        let markdown = try String(
            contentsOf: directory.appendingPathComponent("transcript.md"),
            encoding: .utf8
        )
        let json = try Data(contentsOf: directory.appendingPathComponent("transcript.json"))
        let decoded = try JSONDecoder().decode(TranscriptDocument.self, from: json)
        XCTAssertTrue(markdown.contains("**[1:02:03] me:** A local transcript."))
        XCTAssertEqual(decoded, document)
    }
}
