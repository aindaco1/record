import FluidAudio
import Foundation
import RecordCore
@testable import RecordSpeech
import XCTest

final class RecordSpeechTests: XCTestCase {
    func testOfflinePolicyBlocksDownloadEntryPoint() async {
        RecordFluidAudioOfflinePolicy.enforce()
        XCTAssertTrue(RecordFluidAudioOfflinePolicy.isEnforced)
        do {
            _ = try await ModelHub.fetchWithAuth(
                from: URL(fileURLWithPath: "/network-must-remain-disabled")
            )
            XCTFail("offline speech primitives must block FluidAudio downloads")
        } catch {
            XCTAssertTrue(RecordFluidAudioOfflinePolicy.isEnforced)
        }
    }

    func testPublicResultContractsAreStableAndCodable() throws {
        let result = ParakeetTranscriptResult(
            text: "hello", durationSeconds: 1, confidence: 0.9,
            tokens: [.init(text: "▁hello", tokenId: 1, startsAtSeconds: 0, endsAtSeconds: 1, confidence: 0.9)],
            words: [.init(text: "hello", startsAtSeconds: 0, endsAtSeconds: 1)]
        )
        XCTAssertEqual(try JSONDecoder().decode(ParakeetTranscriptResult.self, from: JSONEncoder().encode(result)), result)
        XCTAssertEqual(ParakeetTranscriber.defaultModelDirectory(for: .v3).lastPathComponent, "parakeet-tdt-0.6b-v3")
    }

    func testSharedModelVerifierRejectsAnIncompleteModel() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        XCTAssertThrowsError(try ParakeetModelVerifier.validateV3(at: root)) { error in
            XCTAssertTrue(String(describing: error).contains("Preprocessor.mlmodelc/coremldata.bin is missing"))
        }
    }
}
