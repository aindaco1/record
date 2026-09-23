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
            ])
        XCTAssertEqual(plan.candidates.map(\.token), ["uh", "I"])
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
        XCTAssertFalse(plan.candidates.contains { $0.token == "very" })

        let result = TranscriptRefiner.apply(
            [
                .init(candidateID: filler.id, action: .remove),
                .init(candidateID: repeatedI.id, action: .remove),
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
                .init(candidateID: repeatedI.id, action: .remove)
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
        XCTAssertEqual(report.policyVersion, "candidate-removal-and-overlap-v2")
        let encoded = try JSONEncoder().encode(report)
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("private synthetic"))
    }

    func testPreservesEmphasisGrammarAndSentenceBoundariesDespiteRemovalAdvice() {
        for text in [
            "It is very very important", "This is really really cold",
            "We waited a long long time", "No no, stop", "She had had enough",
            "I know that that answer is correct", "Go. Go now", "I, I need time",
            "All I hear is I I I.", "We we we should go", "The code is 5 5 2",
        ] {
            let plan = TranscriptRefiner.plan(for: [segment(text)])
            XCTAssertTrue(plan.candidates.isEmpty, text)
            XCTAssertEqual(TranscriptRefiner.apply([], to: plan).segments[0].text, text)
        }
    }

    func testQuotedAndLiteralSegmentsAreProtectedIncludingUnfinishedQuotes() {
        for text in [
            "The word is \"um\" exactly", "Keep 'uh' here", "He said “um we we should go”",
            "The quote begins ‘erm we wait", "Please keep «um» in the caption",
            "The identifier is `um`", "Um, she said \"wait\"", "The quote ends with um”",
        ] {
            XCTAssertTrue(TranscriptRefiner.plan(for: [segment(text)]).candidates.isEmpty, text)
        }
        for text in ["Um, don't go", "Uh, don’t unlock the gate"] {
            XCTAssertEqual(TranscriptRefiner.plan(for: [segment(text)]).candidates.count, 1, text)
        }
    }

    func testRemovalRevalidatesEligibilityEvenForAStaleOrForgedPlan() {
        for (text, index, kind) in [
            ("very very cold", 1, TranscriptRefinementCandidateKind.immediateRepeat),
            ("Keep \"um\" here", 1, .filledPause),
            ("She had had enough", 2, .immediateRepeat),
            ("I. I agree", 1, .immediateRepeat),
            ("I I I agree", 1, .immediateRepeat),
            ("I agree", 0, .filledPause),
        ] {
            let source = segment(text)
            let candidate = TranscriptRefinementCandidate(
                id: "untrusted", kind: kind, segmentIndex: 0, tokenIndex: index,
                speaker: "me", token: String(text.split(separator: " ")[index]),
                leftContext: "", rightContext: "")
            let plan = TranscriptRefinementPlan(
                segments: [source], candidates: [candidate], overlaps: [])
            let result = TranscriptRefiner.apply(
                [.init(candidateID: candidate.id, action: .remove)], to: plan)
            XCTAssertEqual(result.segments, [source], text)
            XCTAssertTrue(result.removals.isEmpty, text)
            XCTAssertTrue(result.acceptedDecisions.isEmpty, text)
        }
    }

    func testSimplePronounAndArticleStuttersRemainEligible() {
        for text in ["I I will go", "We we can wait", "The the key is here", "An an apple fell"] {
            let plan = TranscriptRefiner.plan(for: [segment(text)])
            XCTAssertEqual(plan.candidates.count, 1, text)
            XCTAssertEqual(plan.candidates.first?.kind, .immediateRepeat, text)
        }
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
