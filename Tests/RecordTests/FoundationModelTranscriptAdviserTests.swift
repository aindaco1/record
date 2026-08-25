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
