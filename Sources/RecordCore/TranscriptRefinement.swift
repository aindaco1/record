import CryptoKit
import Foundation

public enum TranscriptRefinementCandidateKind: String, Codable, Equatable, Sendable {
    case filledPause = "filled_pause"
    case immediateRepeat = "immediate_repeat"
}

public struct TranscriptRefinementCandidate: Equatable, Sendable {
    public let id: String
    public let kind: TranscriptRefinementCandidateKind
    public let segmentIndex: Int
    public let tokenIndex: Int
    public let speaker: String
    public let token: String
    public let leftContext: String
    public let rightContext: String

    public init(
        id: String,
        kind: TranscriptRefinementCandidateKind,
        segmentIndex: Int,
        tokenIndex: Int,
        speaker: String,
        token: String,
        leftContext: String,
        rightContext: String
    ) {
        self.id = id
        self.kind = kind
        self.segmentIndex = segmentIndex
        self.tokenIndex = tokenIndex
        self.speaker = speaker
        self.token = token
        self.leftContext = leftContext
        self.rightContext = rightContext
    }
}

public enum TranscriptRefinementAction: String, Codable, Equatable, Sendable {
    case keep
    case remove
}

public struct TranscriptRefinementDecision: Codable, Equatable, Sendable {
    public let candidateID: String
    public let action: TranscriptRefinementAction

    public init(candidateID: String, action: TranscriptRefinementAction) {
        self.candidateID = candidateID
        self.action = action
    }

    enum CodingKeys: String, CodingKey {
        case candidateID = "candidate_id"
        case action
    }
}

public struct TranscriptRefinementRemoval: Codable, Equatable, Sendable {
    public let candidateID: String
    public let kind: TranscriptRefinementCandidateKind

    public init(candidateID: String, kind: TranscriptRefinementCandidateKind) {
        self.candidateID = candidateID
        self.kind = kind
    }

    enum CodingKeys: String, CodingKey {
        case candidateID = "candidate_id"
        case kind
    }
}

public struct TranscriptOverlapGroup: Codable, Equatable, Sendable {
    public let id: String
    public let segmentIndices: [Int]

    public init(id: String, segmentIndices: [Int]) {
        self.id = id
        self.segmentIndices = segmentIndices
    }

    enum CodingKeys: String, CodingKey {
        case id
        case segmentIndices = "segment_indices"
    }
}

public struct TranscriptRefinementPlan: Equatable, Sendable {
    public let segments: [TranscriptDocument.Segment]
    public let candidates: [TranscriptRefinementCandidate]
    public let overlaps: [TranscriptOverlapGroup]

    public init(
        segments: [TranscriptDocument.Segment],
        candidates: [TranscriptRefinementCandidate],
        overlaps: [TranscriptOverlapGroup]
    ) {
        self.segments = segments
        self.candidates = candidates
        self.overlaps = overlaps
    }
}

public struct TranscriptRefinementResult: Equatable, Sendable {
    public let segments: [TranscriptDocument.Segment]
    public let candidateCount: Int
    public let acceptedDecisions: [TranscriptRefinementDecision]
    public let removals: [TranscriptRefinementRemoval]
    public let overlaps: [TranscriptOverlapGroup]

    public var changed: Bool { !removals.isEmpty || !overlaps.isEmpty }

    public init(
        segments: [TranscriptDocument.Segment],
        candidateCount: Int,
        acceptedDecisions: [TranscriptRefinementDecision],
        removals: [TranscriptRefinementRemoval],
        overlaps: [TranscriptOverlapGroup]
    ) {
        self.segments = segments
        self.candidateCount = candidateCount
        self.acceptedDecisions = acceptedDecisions
        self.removals = removals
        self.overlaps = overlaps
    }
}

public enum TranscriptRefinementAdviserOutcome: String, Codable, Equatable, Sendable {
    case notNeeded = "not_needed"
    case usedOnDeviceModel = "used_on_device_model"
    case unavailableOperatingSystem = "unavailable_operating_system"
    case unavailableDevice = "unavailable_device"
    case appleIntelligenceDisabled = "apple_intelligence_disabled"
    case modelNotReady = "model_not_ready"
    case unsupportedLanguage = "unsupported_language"
    case generationFailed = "generation_failed"
    case cancelled
}

public struct TranscriptRefinementReport: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = "record-transcript-refinement-v1"
    public static let currentPolicyVersion = "candidate-removal-and-overlap-v1"

    public let schemaVersion: String
    public let policyVersion: String
    public let sourceSHA256: String
    public let adviserOutcome: TranscriptRefinementAdviserOutcome
    public let candidateCount: Int
    public let decisions: [TranscriptRefinementDecision]
    public let removals: [TranscriptRefinementRemoval]
    public let overlaps: [TranscriptOverlapGroup]

    public init(
        source: TranscriptDocument,
        adviserOutcome: TranscriptRefinementAdviserOutcome,
        result: TranscriptRefinementResult
    ) throws {
        schemaVersion = Self.currentSchemaVersion
        policyVersion = Self.currentPolicyVersion
        sourceSHA256 = Self.sha256(try source.canonicalData())
        self.adviserOutcome = adviserOutcome
        candidateCount = result.candidateCount
        decisions = result.acceptedDecisions
        removals = result.removals
        overlaps = result.overlaps
    }

    public func write(to sessionDirectory: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(self).write(
            to: sessionDirectory.appendingPathComponent("transcript.refinement.json"),
            options: .atomic
        )
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case policyVersion = "policy_version"
        case sourceSHA256 = "source_sha256"
        case adviserOutcome = "adviser_outcome"
        case candidateCount = "candidate_count"
        case decisions
        case removals
        case overlaps
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

public enum TranscriptRefiner {
    public static let maximumCandidates = 120
    private static let contextTokenCount = 6
    private static let maximumContextCharacters = 200
    private static let filledPauses: Set<String> = ["er", "erm", "uh", "uhh", "um", "umm"]
    private static let normalizationLocale = Locale(identifier: "en_US_POSIX")

    public static func plan(
        for segments: [TranscriptDocument.Segment]
    ) -> TranscriptRefinementPlan {
        let overlaps = overlapGroups(in: segments)
        let overlapBySegment = Dictionary(
            uniqueKeysWithValues: overlaps.flatMap { group in
                group.segmentIndices.map { ($0, group.id) }
            }
        )
        let annotated = segments.enumerated().map { index, segment in
            TranscriptDocument.Segment(
                speaker: segment.speaker,
                startMilliseconds: segment.startMilliseconds,
                endMilliseconds: segment.endMilliseconds,
                text: segment.text,
                overlapGroup: overlapBySegment[index] ?? segment.overlapGroup
            )
        }

        var candidates: [TranscriptRefinementCandidate] = []
        for (segmentIndex, segment) in annotated.enumerated() where segment.overlapGroup == nil {
            let tokens = tokens(in: segment.text)
            guard tokens.count > 1 else { continue }
            for tokenIndex in tokens.indices {
                let normalized = normalizedToken(tokens[tokenIndex])
                guard !normalized.isEmpty else { continue }
                let kind: TranscriptRefinementCandidateKind?
                if filledPauses.contains(normalized) {
                    kind = .filledPause
                } else if tokenIndex > 0,
                    normalized == normalizedToken(tokens[tokenIndex - 1]),
                    !normalized.allSatisfy(\.isNumber)
                {
                    kind = .immediateRepeat
                } else {
                    kind = nil
                }
                guard let kind else { continue }
                let leftStart = max(tokens.startIndex, tokenIndex - contextTokenCount)
                let rightEnd = min(tokens.endIndex, tokenIndex + contextTokenCount + 1)
                candidates.append(
                    TranscriptRefinementCandidate(
                        id: candidateID(
                            segmentIndex: segmentIndex,
                            tokenIndex: tokenIndex,
                            kind: kind
                        ),
                        kind: kind,
                        segmentIndex: segmentIndex,
                        tokenIndex: tokenIndex,
                        speaker: segment.speaker,
                        token: tokens[tokenIndex],
                        leftContext: boundedContext(tokens[leftStart..<tokenIndex]),
                        rightContext: boundedContext(tokens[(tokenIndex + 1)..<rightEnd])
                    )
                )
            }
        }

        if candidates.count > maximumCandidates {
            candidates = (0..<maximumCandidates).map { position in
                let index = position * (candidates.count - 1) / (maximumCandidates - 1)
                return candidates[index]
            }
        }
        return TranscriptRefinementPlan(
            segments: annotated,
            candidates: candidates,
            overlaps: overlaps
        )
    }

    public static func apply(
        _ decisions: [TranscriptRefinementDecision],
        to plan: TranscriptRefinementPlan
    ) -> TranscriptRefinementResult {
        let decisionsByID = Dictionary(grouping: decisions, by: \.candidateID)
        let candidateByID = Dictionary(uniqueKeysWithValues: plan.candidates.map { ($0.id, $0) })
        let uniqueDecisions = plan.candidates.compactMap {
            candidate -> TranscriptRefinementDecision? in
            guard let entries = decisionsByID[candidate.id], entries.count == 1 else { return nil }
            return entries[0]
        }
        let requestedRemovals = uniqueDecisions.compactMap {
            decision -> TranscriptRefinementCandidate? in
            guard decision.action == .remove else { return nil }
            return candidateByID[decision.candidateID]
        }
        let removalsBySegment = Dictionary(grouping: requestedRemovals, by: \.segmentIndex)

        var appliedCandidateIDs: Set<String> = []
        let refinedSegments = plan.segments.enumerated().map { index, segment in
            guard let requested = removalsBySegment[index], !requested.isEmpty else {
                return segment
            }
            let sourceTokens = tokens(in: segment.text)
            let valid = requested.filter { candidate in
                sourceTokens.indices.contains(candidate.tokenIndex)
                    && sourceTokens[candidate.tokenIndex] == candidate.token
            }
            let removalIndices = Set(valid.map(\.tokenIndex))
            guard !removalIndices.isEmpty, removalIndices.count < sourceTokens.count else {
                return segment
            }
            appliedCandidateIDs.formUnion(valid.map(\.id))
            return TranscriptDocument.Segment(
                speaker: segment.speaker,
                startMilliseconds: segment.startMilliseconds,
                endMilliseconds: segment.endMilliseconds,
                text: sourceTokens.enumerated().compactMap { tokenIndex, token in
                    removalIndices.contains(tokenIndex) ? nil : token
                }.joined(separator: " "),
                overlapGroup: segment.overlapGroup
            )
        }
        let acceptedDecisions = uniqueDecisions.filter { decision in
            decision.action == .keep || appliedCandidateIDs.contains(decision.candidateID)
        }
        let removals = plan.candidates.compactMap { candidate in
            appliedCandidateIDs.contains(candidate.id)
                ? TranscriptRefinementRemoval(candidateID: candidate.id, kind: candidate.kind)
                : nil
        }
        return TranscriptRefinementResult(
            segments: refinedSegments,
            candidateCount: plan.candidates.count,
            acceptedDecisions: acceptedDecisions,
            removals: removals,
            overlaps: plan.overlaps
        )
    }

    private static func overlapGroups(
        in segments: [TranscriptDocument.Segment]
    ) -> [TranscriptOverlapGroup] {
        guard segments.count > 1 else { return [] }
        var parents = Array(segments.indices)

        func root(_ index: Int) -> Int {
            var current = index
            while parents[current] != current { current = parents[current] }
            return current
        }
        func union(_ first: Int, _ second: Int) {
            let firstRoot = root(first)
            let secondRoot = root(second)
            if firstRoot != secondRoot { parents[secondRoot] = firstRoot }
        }

        for first in segments.indices {
            for second in segments.indices where second > first {
                let left = segments[first]
                let right = segments[second]
                guard left.speaker != right.speaker else { continue }
                let overlaps =
                    max(left.startMilliseconds, right.startMilliseconds)
                    < min(left.endMilliseconds, right.endMilliseconds)
                if overlaps { union(first, second) }
            }
        }

        var grouped: [Int: [Int]] = [:]
        for index in segments.indices {
            grouped[root(index), default: []].append(index)
        }
        let eligible = grouped.values.filter { indices in
            indices.count > 1 && Set(indices.map { segments[$0].speaker }).count > 1
        }.sorted { ($0.min() ?? 0) < ($1.min() ?? 0) }
        return eligible.enumerated().map { position, indices in
            TranscriptOverlapGroup(
                id: String(format: "overlap-%04d", position + 1),
                segmentIndices: indices.sorted()
            )
        }
    }

    private static func tokens(in text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    private static func normalizedToken(_ token: String) -> String {
        token.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: normalizationLocale
        )
        .filter { $0.isLetter || $0.isNumber }
    }

    private static func boundedContext(_ tokens: ArraySlice<String>) -> String {
        String(tokens.joined(separator: " ").prefix(maximumContextCharacters))
    }

    private static func candidateID(
        segmentIndex: Int,
        tokenIndex: Int,
        kind: TranscriptRefinementCandidateKind
    ) -> String {
        String(
            format: "segment-%06d-token-%04d-%@",
            segmentIndex + 1,
            tokenIndex + 1,
            kind.rawValue
        )
    }
}
