import Foundation
import RecordCore
import XCTest

final class TranscriptionCheckpointTests: XCTestCase {
    private func source(_ filename: String, bytes: UInt64 = 100) -> TranscriptionCheckpoint.Source {
        .init(
            filename: filename, speaker: "me", offsetMilliseconds: 20,
            byteCount: bytes, modifiedAt: Date(timeIntervalSince1970: 10))
    }

    func testPartialRetryPreservesSuccessfulSilenceAndRejectsChangedSourceOrEngine() {
        let good = source("mic.wav")
        let checkpoint = TranscriptionCheckpoint(
            engine: "parakeet", model: "v3", language: "en",
            state: .needsRetry,
            tracks: [.init(source: good, segments: []), .init(source: source("system.wav"))])
        XCTAssertTrue(checkpoint.isPartial)
        XCTAssertEqual(checkpoint.completedTracks, 1)
        XCTAssertEqual(
            checkpoint.cachedSegments(for: good, engine: "parakeet", model: "v3", language: "en"),
            [])
        XCTAssertNil(
            checkpoint.cachedSegments(
                for: source("mic.wav", bytes: 101), engine: "parakeet", model: "v3", language: "en")
        )
        XCTAssertNil(
            checkpoint.cachedSegments(for: good, engine: "macwhisper", model: "v3", language: "en"))
        XCTAssertNil(
            checkpoint.cachedSegments(for: good, engine: "parakeet", model: "v3", language: "es"))
    }

    func testCheckpointPersistsDeferredIntentAndRejectsFalseCompletion() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var checkpoint = TranscriptionCheckpoint(
            engine: "test", model: "local", language: "en",
            state: .deferred, tracks: [.init(source: source("mic.wav"))])
        try checkpoint.write(to: directory)
        XCTAssertEqual(try TranscriptionCheckpoint.read(from: directory), checkpoint)
        checkpoint.state = .complete
        XCTAssertThrowsError(try checkpoint.write(to: directory))
        XCTAssertEqual(try TranscriptionCheckpoint.read(from: directory).state, .deferred)
    }
}
