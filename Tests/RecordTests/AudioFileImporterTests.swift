import AVFoundation
import Foundation
@testable import Record
import RecordCore
import XCTest

final class AudioFileImporterTests: XCTestCase {
    private func fixture() throws -> (URL, URL, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let output = root.appendingPathComponent("exports")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("Synthetic Dust Wave.wav")
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let file = try AVAudioFile(forWriting: source, settings: format.settings)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1_600))
        buffer.frameLength = 1_600
        for index in 0..<1_600 { buffer.floatChannelData![0][index] = 0 }
        try file.write(from: buffer)
        return (root, source, output)
    }

    func testImportCopiesWithoutOverwritingAndUsesExistingTranscriptionPipeline() async throws {
        let (root, source, output) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = try Data(contentsOf: source)
        let first = try AudioFileImporter.importFile(source, into: output)
        let second = try AudioFileImporter.importFile(source, into: output)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(try Data(contentsOf: source), original)
        XCTAssertEqual(try Data(contentsOf: first.appendingPathComponent("source.wav")), original)
        let manifest = try SessionManifest.read(from: first)
        XCTAssertEqual(manifest.importedAudio?.originalFilename, source.lastPathComponent)
        XCTAssertEqual(manifest.importedAudio?.durationMilliseconds, 100)
        XCTAssertEqual(manifest.tracks.map(\.kind), [.importedAudio])
        XCTAssertEqual(TranscriptionCoordinator.pendingSessionDirectories(root: output).count, 2)
        let coordinator = TranscriptionCoordinator(
            engineFactory: { _ in SyntheticEngine() },
            refinementEnabled: { false }, transcriptionEnabled: { false },
            vocabulary: { Vocabulary(terms: [.init(preferred: "Dust Wave")]) })
        try await coordinator.transcribe(first)
        let transcript = try JSONDecoder().decode(
            TranscriptDocument.self,
            from: Data(contentsOf: first.appendingPathComponent("transcript.json")))
        XCTAssertEqual(transcript.segments.first?.speaker, "source")
        XCTAssertEqual(transcript.segments.first?.text, "Dust Wave")
        let raw = try JSONDecoder().decode(
            TranscriptDocument.self,
            from: Data(contentsOf: first.appendingPathComponent("transcript.raw.json")))
        XCTAssertEqual(raw.segments.first?.text, "dustwave")
        XCTAssertEqual(try TranscriptionCheckpoint.read(from: first).state, .complete)
        XCTAssertEqual(try Data(contentsOf: source), original)
    }

    func testRejectsSymlinksAndCorruptFilesWithoutPublishingPartialSessions() throws {
        let (root, source, output) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let symlink = root.appendingPathComponent("linked.wav")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: source)
        XCTAssertThrowsError(try AudioFileImporter.importFile(symlink, into: output))
        let malformed = root.appendingPathComponent("broken.wav")
        try Data("not audio".utf8).write(to: malformed)
        XCTAssertThrowsError(try AudioFileImporter.importFile(malformed, into: output))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: output.path).isEmpty)
        XCTAssertEqual(try String(contentsOf: malformed, encoding: .utf8), "not audio")
    }

    func testHiddenStagingDirectoryCannotEnterQueue() throws {
        let (root, source, output) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let imported = try AudioFileImporter.importFile(source, into: output)
        let staged = output.appendingPathComponent(".record-import-interrupted")
        try FileManager.default.moveItem(at: imported, to: staged)
        XCTAssertTrue(TranscriptionCoordinator.pendingSessionDirectories(root: output).isEmpty)
    }

    func testCancelledBatchDoesNotCopyAnotherSource() async throws {
        let (root, source, output) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = try Data(contentsOf: source)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await AudioFileImporter.importInBackground(source, into: output)
        }
        do {
            _ = try await task.value
            XCTFail("A cancelled import must not publish a session")
        } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: output.path).isEmpty)
        XCTAssertEqual(try Data(contentsOf: source), original)
    }
}

private struct SyntheticEngine: TranscriptionEngine {
    let name = "synthetic"
    let model = "fixture"
    func prepare() async throws {}
    func release() async {}
    func transcribe(_ audio: URL) async throws -> [TranscriptSegment] {
        [.init(start: 0, end: 0.1, text: "dustwave")]
    }
}
