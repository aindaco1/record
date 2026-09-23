@testable import Record
import RecordCore
import XCTest

final class FoundationModelTranscriptAdviserTests: XCTestCase {
    func testAdvicePolicyAcceptsOnlyUniqueKnownActionsAndIndexes() {
        let candidates = [candidate(id: "one"), candidate(id: "two"), candidate(id: "three")]
        let proposals = [
            TranscriptRefinementProposal(candidateIndex: 0, action: "remove"),
            TranscriptRefinementProposal(candidateIndex: 1, action: "keep"),
            TranscriptRefinementProposal(candidateIndex: 1, action: "remove"),
            TranscriptRefinementProposal(candidateIndex: 2, action: "rewrite"),
            TranscriptRefinementProposal(candidateIndex: 99, action: "remove"),
        ]

        XCTAssertEqual(
            TranscriptRefinementAdvicePolicy.decisions(
                from: proposals,
                candidates: candidates
            ),
            [TranscriptRefinementDecision(candidateID: "one", action: .remove)]
        )
    }

    func testEmptyCandidateListDoesNotInvokeTheModel() async {
        let result = await OnDeviceTranscriptRefinementAdviser().advise(
            candidates: [],
            language: "auto"
        )

        XCTAssertEqual(result, TranscriptRefinementAdvice(decisions: [], outcome: .notNeeded))
    }

    func testExperimentsDoNotChangeTheProductionDefaultOrInvokeEmptyInference() async {
        XCTAssertEqual(OnDeviceTranscriptRefinementAdviser().modelProfile, .general)
        XCTAssertEqual(TranscriptAdviserExperiment.baseline.modelProfile, .contentTagging)
        for variant in [
            TranscriptAdviserExperiment.production, .baseline, .general,
            .generalBoolean, .generalSentence,
        ] {
            let result = await variant.adviser(segments: []).advise(candidates: [], language: "en")
            XCTAssertEqual(result, TranscriptRefinementAdvice(decisions: [], outcome: .notNeeded))
        }
    }

    func testSentenceExperimentPreservesCandidateIdentityAndRemovalContract() {
        let segments = [
            TranscriptDocument.Segment(
                speaker: "me", startMilliseconds: 0, endMilliseconds: 5000,
                text:
                    "Keep this separate. I was carefully choosing which of the available words to use, um, before replying. This is unrelated."
            )
        ]
        let original = TranscriptRefiner.plan(for: segments)
        let candidate = original.candidates[0]
        let expanded = SentenceContextExperiment(segments: segments).contextualize(candidate)
        XCTAssertEqual(expanded.id, candidate.id)
        XCTAssertEqual(expanded.tokenIndex, candidate.tokenIndex)
        XCTAssertEqual(expanded.token, candidate.token)
        XCTAssertTrue(expanded.leftContext.hasPrefix("I was carefully"))
        XCTAssertFalse(expanded.leftContext.contains("Keep this separate"))
        XCTAssertEqual(expanded.rightContext, "before replying.")
        let withContext = TranscriptRefinementPlan(
            segments: original.segments, candidates: [expanded], overlaps: original.overlaps)
        let decision = TranscriptRefinementDecision(candidateID: candidate.id, action: .remove)
        XCTAssertEqual(
            TranscriptRefiner.apply([decision], to: original),
            TranscriptRefiner.apply([decision], to: withContext))
    }

    func testSentenceContextIsBoundedAndUnknownTokensRemainUnchanged() {
        let segments = [
            TranscriptDocument.Segment(
                speaker: "me", startMilliseconds: 0, endMilliseconds: 5000,
                text: String(repeating: "before ", count: 100) + "um "
                    + String(repeating: "after ", count: 100) + "."
            )
        ]
        let candidate = TranscriptRefiner.plan(for: segments).candidates.first { $0.token == "um" }!
        let experiment = SentenceContextExperiment(segments: segments)
        let expanded = experiment.contextualize(candidate)
        XCTAssertEqual(expanded.leftContext.count, 200)
        XCTAssertEqual(expanded.rightContext.count, 200)
        let unknown = self.candidate(id: "unknown")
        XCTAssertEqual(experiment.contextualize(unknown), unknown)
    }

    private func candidate(id: String) -> TranscriptRefinementCandidate {
        TranscriptRefinementCandidate(
            id: id,
            kind: .filledPause,
            segmentIndex: 0,
            tokenIndex: 0,
            speaker: "me",
            token: "um",
            leftContext: "",
            rightContext: "hello"
        )
    }
}
