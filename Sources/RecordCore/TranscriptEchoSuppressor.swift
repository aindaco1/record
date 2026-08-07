import Foundation

public struct TranscriptEchoSuppressionResult: Equatable, Sendable {
    public let segments: [TranscriptDocument.Segment]
    public let suppressedMicrophoneSegments: [TranscriptDocument.Segment]

    public init(
        segments: [TranscriptDocument.Segment],
        suppressedMicrophoneSegments: [TranscriptDocument.Segment]
    ) {
        self.segments = segments
        self.suppressedMicrophoneSegments = suppressedMicrophoneSegments
    }
}

/// Removes only high-confidence acoustic echoes from the readable transcript.
/// The caller remains responsible for preserving the unsuppressed segments so
/// this derivative is reversible. Raw microphone and system media are never
/// changed.
public enum TranscriptEchoSuppressor {
    private static let timingPaddingMilliseconds = 600
    private static let maximumStartDeltaMilliseconds = 1_000

    public static func suppress(
        _ segments: [TranscriptDocument.Segment],
        microphoneSpeaker: String = "me",
        systemSpeaker: String = "them"
    ) -> TranscriptEchoSuppressionResult {
        let systemSegments = segments.filter { $0.speaker == systemSpeaker }
        let microphoneSegments = segments.filter { $0.speaker == microphoneSpeaker }
        let longEchoes = microphoneSegments.filter { microphone in
            normalizedWords(microphone.text).count >= 3
                && isHighConfidenceEcho(microphone, of: systemSegments)
        }
        var kept: [TranscriptDocument.Segment] = []
        var suppressed: [TranscriptDocument.Segment] = []

        for segment in segments {
            guard segment.speaker == microphoneSpeaker else {
                kept.append(segment)
                continue
            }
            let words = normalizedWords(segment.text)
            let isEcho =
                isHighConfidenceEcho(segment, of: systemSegments)
                || isShortEchoInsideContinuousRun(
                    segment,
                    words: words,
                    systemSegments: systemSegments,
                    longEchoes: longEchoes
                )
            guard isEcho
            else {
                kept.append(segment)
                continue
            }
            suppressed.append(segment)
        }

        return TranscriptEchoSuppressionResult(
            segments: kept,
            suppressedMicrophoneSegments: suppressed
        )
    }

    private static func isHighConfidenceEcho(
        _ microphone: TranscriptDocument.Segment,
        of systemSegments: [TranscriptDocument.Segment]
    ) -> Bool {
        let microphoneWords = normalizedWords(microphone.text)
        // Short acknowledgements are common genuine backchannels. Keep them
        // even when the far end happened to say the same one or two words.
        guard microphoneWords.count >= 3 else { return false }

        let candidates = systemSegments.filter { system in
            intervalsOverlap(
                startA: microphone.startMilliseconds,
                endA: microphone.endMilliseconds,
                startB: system.startMilliseconds - timingPaddingMilliseconds,
                endB: system.endMilliseconds + timingPaddingMilliseconds
            )
                && abs(system.startMilliseconds - microphone.startMilliseconds)
                    <= maximumStartDeltaMilliseconds
        }
        guard !candidates.isEmpty else { return false }

        for candidate in candidates {
            let systemWords = normalizedWords(candidate.text)
            guard !systemWords.isEmpty else { continue }
            let matched = longestCommonSubsequenceLength(microphoneWords, systemWords)
            let coverage = Double(matched) / Double(microphoneWords.count)

            if microphoneWords.count == 3 {
                if microphoneWords == systemWords { return true }
            } else if coverage >= 0.80 {
                return true
            }
        }
        return false
    }

    private static func isShortEchoInsideContinuousRun(
        _ microphone: TranscriptDocument.Segment,
        words: [String],
        systemSegments: [TranscriptDocument.Segment],
        longEchoes: [TranscriptDocument.Segment]
    ) -> Bool {
        guard (1...2).contains(words.count) else { return false }
        let hasExactAlignedSystemCopy = systemSegments.contains { system in
            intervalsOverlap(
                startA: microphone.startMilliseconds,
                endA: microphone.endMilliseconds,
                startB: system.startMilliseconds - timingPaddingMilliseconds,
                endB: system.endMilliseconds + timingPaddingMilliseconds
            )
                && abs(system.startMilliseconds - microphone.startMilliseconds)
                    <= maximumStartDeltaMilliseconds
                && normalizedWords(system.text) == words
        }
        guard hasExactAlignedSystemCopy else { return false }

        // A standalone one- or two-word overlap may be a real backchannel.
        // Suppress it only when longer high-confidence echoes directly bracket
        // it, proving that Parakeet split one continuous acoustic echo run.
        let continuityMilliseconds = 1_000
        let hasPrecedingEcho = longEchoes.contains { echo in
            echo.endMilliseconds <= microphone.startMilliseconds
                && microphone.startMilliseconds - echo.endMilliseconds
                    <= continuityMilliseconds
        }
        let hasFollowingEcho = longEchoes.contains { echo in
            echo.startMilliseconds >= microphone.endMilliseconds
                && echo.startMilliseconds - microphone.endMilliseconds
                    <= continuityMilliseconds
        }
        return hasPrecedingEcho && hasFollowingEcho
    }

    private static func intervalsOverlap(
        startA: Int,
        endA: Int,
        startB: Int,
        endB: Int
    ) -> Bool {
        max(startA, startB) <= min(endA, endB)
    }

    private static func normalizedWords(_ text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
    }

    private static func longestCommonSubsequenceLength(
        _ first: [String],
        _ second: [String]
    ) -> Int {
        guard !first.isEmpty, !second.isEmpty else { return 0 }
        var previous = Array(repeating: 0, count: second.count + 1)
        var current = previous

        for left in first {
            current[0] = 0
            for index in second.indices {
                current[index + 1] =
                    left == second[index]
                    ? previous[index] + 1
                    : max(previous[index + 1], current[index])
            }
            swap(&previous, &current)
        }
        return previous[second.count]
    }
}
