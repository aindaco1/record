import Foundation
import RecordCore
import XCTest

final class VocabularyTests: XCTestCase {
    private func source(_ text: String) -> TranscriptDocument {
        TranscriptDocument(
            engine: "synthetic", model: "fixture", createdAt: "2026-10-03T00:00:00Z",
            segments: [
                .init(
                    speaker: "me", startMilliseconds: 123, endMilliseconds: 2000, text: text,
                    overlapGroup: "overlap-1")
            ],
            incompleteTrackCount: 1)
    }

    func testGlobalCaseSpacingAndExplicitAliasesPreserveMetadataAndUnrelatedText() throws {
        let vocabulary = Vocabulary(terms: [.init(preferred: "Dust Wave", aliases: ["dust waive"])])
        let original = source(
            "DUSTWAVE, dust-wave, dust wave, Dustwave and dust waive. Dustwaver 42 café cafe\u{301} `dustwave`."
        )
        let result = try vocabulary.apply(to: original)
        XCTAssertEqual(
            result.transcript.segments[0].text,
            "Dust Wave, Dust Wave, Dust Wave, Dust Wave and Dust Wave. Dustwaver 42 café cafe\u{301} `dustwave`."
        )
        XCTAssertEqual(result.transcript.segments[0].startMilliseconds, 123)
        XCTAssertEqual(result.transcript.segments[0].endMilliseconds, 2000)
        XCTAssertEqual(result.transcript.segments[0].overlapGroup, "overlap-1")
        XCTAssertEqual(result.transcript.incompleteTrackCount, 1)
        XCTAssertEqual(result.changes.count, 1)
        XCTAssertEqual(result.changes[0].before, original.segments[0].text)
    }

    func testMatchingDoesNotCascadeAndLongestTermWins() throws {
        let vocabulary = Vocabulary(terms: [
            .init(preferred: "Alpine", aliases: ["alpha"]),
            .init(preferred: "Alpine Studio", aliases: ["alpha studio"]),
        ])
        XCTAssertEqual(
            try vocabulary.apply(to: source("alpha studio / alpha / alphabet")).transcript.segments[
                0
            ].text,
            "Alpine Studio / Alpine / alphabet")
        XCTAssertThrowsError(
            try Vocabulary(terms: [.init(preferred: "Dust Wave"), .init(preferred: "Dustwave")])
                .validate())
        XCTAssertThrowsError(try Vocabulary(terms: [.init(preferred: "\n")]).validate())
    }

    func testReapplyUsesPreservedSourceAndCanUndoRemovedRules() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = source("dustwave")
        let vocabulary = Vocabulary(terms: [.init(preferred: "Dust Wave")])
        try original.writeJSON(to: directory.appendingPathComponent("transcript.raw.json"))
        try TranscriptVocabulary.write(source: original, vocabulary: vocabulary, to: directory)
        let corrected = try Data(contentsOf: directory.appendingPathComponent("transcript.json"))
        try TranscriptVocabulary.reapply(vocabulary: vocabulary, to: directory)
        XCTAssertEqual(
            try Data(contentsOf: directory.appendingPathComponent("transcript.json")), corrected)
        try TranscriptVocabulary.reapply(vocabulary: Vocabulary(), to: directory)
        XCTAssertEqual(
            try JSONDecoder().decode(
                TranscriptDocument.self,
                from: Data(contentsOf: directory.appendingPathComponent("transcript.json"))
            ).canonicalData(), try original.canonicalData())
        XCTAssertEqual(
            try JSONDecoder().decode(
                TranscriptDocument.self,
                from: Data(contentsOf: directory.appendingPathComponent("transcript.raw.json"))
            ).canonicalData(), try original.canonicalData())
    }

    func testRefusesSymlinkOutputs() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appendingPathComponent("untouched")
        try Data("safe".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(
            at: directory.appendingPathComponent("transcript.md"), withDestinationURL: target)
        XCTAssertThrowsError(
            try TranscriptVocabulary.write(
                source: source("dustwave"), vocabulary: Vocabulary(), to: directory))
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "safe")
    }
}
