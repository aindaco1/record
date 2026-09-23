import CryptoKit
import DustWaveAppleIntelligence
import Foundation
@testable import Record
import RecordCore
import XCTest

/// Explicit development probe. Ordinary Swift/CI tests never invoke Apple inference.
final class TranscriptJevProbeTests: XCTestCase {
    func testPublicSyntheticCleanup() async throws {
        guard let destination = ProcessInfo.processInfo.environment["RECORD_JEV_OUTPUT"] else {
            throw XCTSkip("Run node scripts/test.mjs for native cleanup and Jev evaluation")
        }
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let suite = ProcessInfo.processInfo.environment["RECORD_JEV_SUITE"] ?? "baseline"
        let file = try XCTUnwrap(
            [
                "baseline": "transcript-cleanup.json",
                "regressions": "transcript-cleanup-regressions.json",
            ][suite])
        let data = try Data(
            contentsOf: root.appendingPathComponent("scripts/qa/fixtures/\(file)"))
        let fixtures = try JSONDecoder().decode([Fixture].self, from: data)
        let variant = try XCTUnwrap(
            TranscriptAdviserExperiment(
                rawValue:
                    ProcessInfo.processInfo.environment["RECORD_JEV_VARIANT"] ?? "production")
        )
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let output = URL(fileURLWithPath: destination)
        guard !FileManager.default.fileExists(atPath: output.path) else {
            XCTFail("The native probe must not overwrite previous evidence")
            return
        }
        var evidence = Evidence(
            fixtureSHA256: hash, suite: suite, complete: false,
            environment: NativeEnvironment(variant: variant), cases: []
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        for fixture in fixtures {
            let suppression = TranscriptEchoSuppressor.suppress(fixture.segments)
            let source = TranscriptDocument(
                engine: "synthetic", model: "none", createdAt: "synthetic",
                segments: suppression.segments
            )
            let pass = await TranscriptionCoordinator.refinementPass(
                source: source, language: "en",
                adviser: variant.adviser(segments: source.segments)
            )
            evidence.cases.append(
                CaseResult(
                    id: fixture.id, outcome: pass.outcome.rawValue,
                    candidateCount: pass.result.candidateCount,
                    segments: pass.result.segments
                )
            )
            try encoder.encode(evidence).write(to: output, options: .atomic)
        }
        evidence.complete = true
        try encoder.encode(evidence).write(to: output, options: .atomic)
    }

    private struct Fixture: Decodable {
        let id: String
        let segments: [TranscriptDocument.Segment]
    }

    private struct Evidence: Encodable {
        let fixtureSHA256: String
        let suite: String
        var complete: Bool
        let environment: NativeEnvironment
        var cases: [CaseResult]
    }

    private struct NativeEnvironment: Encodable {
        let variant: String
        let useCase: String
        let refinementPolicy = TranscriptRefinementReport.currentPolicyVersion
        let operatingSystem: String
        let appleModel: AppleModelMetadata?

        init(variant: TranscriptAdviserExperiment) {
            self.variant = variant.rawValue
            useCase = variant.modelProfile.rawValue
            operatingSystem = ProcessInfo.processInfo.operatingSystemVersionString
            if #available(macOS 26.0, *) {
                appleModel = AppleGeneration.metadata(for: variant.modelProfile.makeModel())
            } else {
                appleModel = nil
            }
        }
    }

    private struct CaseResult: Encodable {
        let id: String
        let outcome: String
        let candidateCount: Int
        let segments: [TranscriptDocument.Segment]
    }
}
