import DustWaveAppleIntelligence
import Foundation
import FoundationModels
import NaturalLanguage
@testable import Record
import RecordCore

/// Test-target-only variants. The production runner still uses the app's default adviser.
enum TranscriptAdviserExperiment: String {
    case production
    case baseline
    case general
    case generalBoolean = "general-boolean"
    case generalSentence = "general-sentence"

    var modelProfile: TranscriptRefinementModelProfile {
        switch self {
        case .production: OnDeviceTranscriptRefinementAdviser().modelProfile
        case .baseline: .contentTagging
        default: .general
        }
    }

    func adviser(segments: [TranscriptDocument.Segment]) -> any TranscriptRefinementAdvising {
        switch self {
        case .generalBoolean: BooleanRemovalExperiment()
        case .generalSentence: SentenceContextExperiment(segments: segments)
        default: OnDeviceTranscriptRefinementAdviser(modelProfile: modelProfile)
        }
    }
}

private struct BooleanRemovalExperiment: TranscriptRefinementAdvising {
    func advise(
        candidates: [TranscriptRefinementCandidate], language: String
    ) async -> TranscriptRefinementAdvice {
        guard !candidates.isEmpty else {
            return TranscriptRefinementAdvice(decisions: [], outcome: .notNeeded)
        }
        let capability = OnDeviceTranscriptRefinementAdviser.currentCapability(
            language: language, modelProfile: .general)
        guard capability.canEnable, #available(macOS 26.0, *) else {
            return TranscriptRefinementAdvice(
                decisions: [], outcome: capability.unavailableOutcome ?? .generationFailed)
        }
        do {
            var decisions: [TranscriptRefinementDecision] = []
            for candidate in candidates {
                let response = try await AppleGeneration.respond(
                    to: OnDeviceTranscriptRefinementAdviser.prompt(for: [candidate]),
                    generating: BooleanRemoval.self,
                    model: TranscriptRefinementModelProfile.general.makeModel(),
                    instructions: OnDeviceTranscriptRefinementAdviser.instructions,
                    maximumResponseTokens: 512
                )
                decisions.append(
                    TranscriptRefinementDecision(
                        candidateID: candidate.id, action: response.content.remove ? .remove : .keep
                    ))
            }
            return TranscriptRefinementAdvice(decisions: decisions, outcome: .usedOnDeviceModel)
        } catch is CancellationError {
            return TranscriptRefinementAdvice(decisions: [], outcome: .cancelled)
        } catch {
            return TranscriptRefinementAdvice(decisions: [], outcome: .generationFailed)
        }
    }
}

@available(macOS 26.0, *)
@Generable
private struct BooleanRemoval {
    @Guide(description: "True only when this candidate is safe to remove under the instructions")
    var remove: Bool
}

struct SentenceContextExperiment: TranscriptRefinementAdvising {
    let segments: [TranscriptDocument.Segment]

    func advise(
        candidates: [TranscriptRefinementCandidate], language: String
    ) async -> TranscriptRefinementAdvice {
        await OnDeviceTranscriptRefinementAdviser(modelProfile: .general).advise(
            candidates: candidates.map(contextualize), language: language)
    }

    func contextualize(_ candidate: TranscriptRefinementCandidate) -> TranscriptRefinementCandidate
    {
        guard segments.indices.contains(candidate.segmentIndex) else { return candidate }
        let text = segments[candidate.segmentIndex].text
        let tokens = text.split(whereSeparator: \.isWhitespace)
        guard tokens.indices.contains(candidate.tokenIndex),
            tokens[candidate.tokenIndex] == candidate.token
        else { return candidate }
        let token = tokens[candidate.tokenIndex]
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        tokenizer.setLanguage(.english)
        let sentence = tokenizer.tokenRange(at: token.startIndex)
        guard sentence.lowerBound <= token.startIndex, sentence.upperBound >= token.endIndex else {
            return candidate
        }
        let left = text[sentence.lowerBound..<token.startIndex]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let right = text[token.endIndex..<sentence.upperBound]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return TranscriptRefinementCandidate(
            id: candidate.id, kind: candidate.kind, segmentIndex: candidate.segmentIndex,
            tokenIndex: candidate.tokenIndex, speaker: candidate.speaker, token: candidate.token,
            leftContext: String(left.suffix(200)), rightContext: String(right.prefix(200))
        )
    }
}
