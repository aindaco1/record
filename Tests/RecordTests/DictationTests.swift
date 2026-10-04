import Foundation
@testable import Record
import RecordCore
import XCTest

final class DictationTests: XCTestCase, @unchecked Sendable {
    @MainActor
    func testDeferringAPreviewReleasesThePendingDictation() {
        let preview = DictationPreviewController()
        let directory = URL(fileURLWithPath: "/tmp/synthetic-dictation")
        preview.begin(directory: directory, retaining: nil)
        XCTAssertTrue(preview.isProcessing)
        preview.update(.deferred(session: "another-session"))
        XCTAssertTrue(preview.isProcessing)
        preview.update(.deferred(session: directory.lastPathComponent))
        XCTAssertFalse(preview.isProcessing)
    }

    func testPlainTextOmitsSpeakerLabelsAndTimestampsAndPreservesWords() {
        let document = TranscriptDocument(
            engine: "synthetic", model: "test", createdAt: "test",
            segments: [
                .init(
                    speaker: "me", startMilliseconds: 0, endMilliseconds: 100, text: "  Hello.\n"),
                .init(speaker: "me", startMilliseconds: 100, endMilliseconds: 200, text: " \n"),
                .init(
                    speaker: "me", startMilliseconds: 200, endMilliseconds: 300, text: "Dust Wave."),
            ])
        XCTAssertEqual(document.plainText, "Hello. Dust Wave.")
    }
    func testDictationTranscribesAndResumesWhenAutomaticRecordingTranscriptionIsOff() async throws {
        for resume in [false, true] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(
                UUID().uuidString)
            let session = root.appendingPathComponent("synthetic")
            try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }
            try SessionManifest(
                state: .finalized, startedAt: Date(timeIntervalSince1970: 1),
                endedAt: Date(timeIntervalSince1970: 2),
                tracks: [.init(kind: .microphone, filename: "mic.wav")], purpose: .dictation
            ).write(to: session)
            let source = Data("synthetic source".utf8)
            try source.write(to: session.appendingPathComponent("mic.wav"))
            let done = expectation(description: "explicit dictation completes")
            let coordinator = TranscriptionCoordinator(
                notificationHandler: { _ in }, engineFactory: { _ in DictationEngine() },
                refinementEnabled: { false }, transcriptionEnabled: { false },
                vocabulary: { .init(terms: [.init(preferred: "Dust Wave", aliases: ["dustwave"])]) }
            )
            await coordinator.setStatusHandler { status in
                if case .finished(_, let success) = status {
                    XCTAssertTrue(success)
                    done.fulfill()
                }
            }
            if resume {
                await coordinator.resumePending(root: root, recoverInterrupted: false)
            } else {
                await coordinator.enqueue(session)
            }
            await fulfillment(of: [done], timeout: 5)
            XCTAssertEqual(
                try TranscriptPreviewReader.read(directory: session).plainText,
                "Hello Dust Wave.")
            XCTAssertEqual(try Data(contentsOf: session.appendingPathComponent("mic.wav")), source)
            XCTAssertEqual(try SessionManifest.read(from: session).purpose, .dictation)
        }
    }

    func testPreviewReaderRejectsPathsLinksAndOversizedFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertThrowsError(
            try TranscriptPreviewReader.read(directory: root, filename: "../outside.json"))
        let file = root.appendingPathComponent("transcript.json")
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: root)
        XCTAssertThrowsError(try TranscriptPreviewReader.read(directory: root))
        try FileManager.default.removeItem(at: file)
        try Data(repeating: 32, count: 8 * 1_024 * 1_024 + 1).write(to: file)
        XCTAssertThrowsError(try TranscriptPreviewReader.read(directory: root))
    }
}

private struct DictationEngine: TranscriptionEngine {
    let name = "synthetic"
    let model = "test"
    func prepare() async throws {}
    func release() async {}
    func transcribe(_ audio: URL) async throws -> [TranscriptSegment] {
        [.init(start: 0, end: 1, text: "Hello dustwave.")]
    }
}
