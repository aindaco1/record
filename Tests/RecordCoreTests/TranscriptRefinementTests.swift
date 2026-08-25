import Foundation
import RecordCore
import XCTest

final class TranscriptRefinementTests: XCTestCase {
    func testPlansOnlyBoundedFilledPauseAndImmediateRepeatCandidates() {
        let segments = [
            segment("I uh I I think this is very very important"),
            segment("Ah yes, 10 10 is still a number", start: 5_000),
        ]

        let plan = TranscriptRefiner.plan(for: segments)

        XCTAssertEqual(
            plan.candidates.map(\.kind),
            [
                .filledPause,
                .immediateRepeat,
                .immediateRepeat,
            ])
        XCTAssertEqual(plan.candidates.map(\.token), ["uh", "I", "very"])
        XCTAssertFalse(plan.candidates.contains { $0.token == "Ah" })
        XCTAssertFalse(plan.candidates.contains { $0.token == "10" })
    }

    func testOverlapIsExplicitAndExcludedFromRemovalCandidates() {
        let segments = [
            segment("uh I was speaking", speaker: "me", start: 0, end: 2_000),
            segment("yes yes I know", speaker: "them", start: 1_000, end: 3_000),
            segment("um later", speaker: "me", start: 4_000, end: 5_000),
        ]

        let plan = TranscriptRefiner.plan(for: segments)

        XCTAssertEqual(
            plan.overlaps,
            [
                TranscriptOverlapGroup(id: "overlap-0001", segmentIndices: [0, 1])
            ])
        XCTAssertEqual(
            plan.segments.map(\.overlapGroup),
            [
                "overlap-0001", "overlap-0001", nil,
            ])
        XCTAssertEqual(plan.candidates.map(\.token), ["um"])
    }

    func testAppliesOnlyUniqueKnownValidatedRemovalDecisions() throws {
        let original = segment("I uh I I think this is very very important")
        let plan = TranscriptRefiner.plan(for: [original])
        let filler = try XCTUnwrap(plan.candidates.first { $0.kind == .filledPause })
        let repeatedI = try XCTUnwrap(
            plan.candidates.first { $0.kind == .immediateRepeat && $0.token == "I" }
        )
        let emphaticVery = try XCTUnwrap(plan.candidates.first { $0.token == "very" })

        let result = TranscriptRefiner.apply(
            [
                .init(candidateID: filler.id, action: .remove),
                .init(candidateID: repeatedI.id, action: .remove),
                .init(candidateID: emphaticVery.id, action: .keep),
                .init(candidateID: "invented", action: .remove),
                .init(candidateID: filler.id, action: .remove),
            ], to: plan)

        XCTAssertEqual(
            result.segments.first?.text,
            "I uh I think this is very very important",
            "A duplicate decision must invalidate that candidate instead of deleting twice"
        )
        XCTAssertEqual(result.segments.first?.speaker, original.speaker)
        XCTAssertEqual(result.segments.first?.startMilliseconds, original.startMilliseconds)
        XCTAssertEqual(result.segments.first?.endMilliseconds, original.endMilliseconds)
        XCTAssertEqual(
            result.removals,
            [
                .init(candidateID: repeatedI.id, kind: .immediateRepeat)
            ])
        XCTAssertEqual(
            result.acceptedDecisions,
            [
                .init(candidateID: repeatedI.id, action: .remove),
                .init(candidateID: emphaticVery.id, action: .keep),
            ])
    }

    func testNeverDeletesAnEntireUtterance() throws {
        let plan = TranscriptRefiner.plan(for: [segment("uh um")])
        let decisions = plan.candidates.map {
            TranscriptRefinementDecision(candidateID: $0.id, action: .remove)
        }

        let result = TranscriptRefiner.apply(decisions, to: plan)

        XCTAssertEqual(result.segments.first?.text, "uh um")
        XCTAssertTrue(result.removals.isEmpty)
        XCTAssertTrue(result.acceptedDecisions.isEmpty)
    }

    func testLongTranscriptCandidatesAreSampledAcrossItsDuration() throws {
        let segments = (0..<500).map { index in
            segment("word uh next", start: index * 2_000, end: index * 2_000 + 1_000)
        }

        let plan = TranscriptRefiner.plan(for: segments)

        XCTAssertEqual(plan.candidates.count, TranscriptRefiner.maximumCandidates)
        XCTAssertEqual(plan.candidates.first?.segmentIndex, 0)
        XCTAssertEqual(plan.candidates.last?.segmentIndex, 499)
    }

    func testReportBindsSourceWithoutDuplicatingTranscriptText() throws {
        let source = TranscriptDocument(
            engine: "fixture",
            model: "local",
            createdAt: "2026-08-25T00:00:00Z",
            segments: [segment("private synthetic sentence")]
        )
        let plan = TranscriptRefiner.plan(for: source.segments)
        let result = TranscriptRefiner.apply([], to: plan)
        let report = try TranscriptRefinementReport(
            source: source,
            adviserOutcome: .notNeeded,
            result: result
        )

        XCTAssertEqual(report.sourceSHA256.count, 64)
        XCTAssertEqual(report.schemaVersion, "record-transcript-refinement-v1")
        let encoded = try JSONEncoder().encode(report)
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("private synthetic"))
    }

    private func segment(
        _ text: String,
        speaker: String = "me",
        start: Int = 0,
        end: Int = 1_000
    ) -> TranscriptDocument.Segment {
        .init(
            speaker: speaker,
            startMilliseconds: start,
            endMilliseconds: end,
            text: text
        )
    }
}
