import Foundation
import RecordCore
import RecordSpeech

/// Local Parakeet transcription via FluidAudio's Core ML port. Model files
/// must already exist in the managed cache; this engine never downloads them.
actor ParakeetEngine: TranscriptionEngine {
    enum EngineError: Error, CustomStringConvertible {
        case notPrepared
        case unreadableAudio(URL, Error?)
        case modelsMissing(URL)

        var description: String {
            switch self {
            case .notPrepared: return "parakeet engine used before prepare()"
            case .unreadableAudio(let url, let e):
                return "unreadable or empty audio \(url.lastPathComponent)"
                    + (e.map { ": \($0)" } ?? "")
            case .modelsMissing(let url):
                return "local transcription model is missing at \(url.path)"
            }
        }
    }

    nonisolated let name = "parakeet"
    nonisolated let model: String

    private let transcriber: ParakeetTranscriber

    init(selection: ParakeetModelID) {
        model = selection.rawValue
        transcriber = ParakeetTranscriber(model: selection)
    }

    func prepare() async throws {
        FluidAudioOfflinePolicy.enforce()
        do {
            try await transcriber.prepare()
        } catch let error as ParakeetTranscriber.TranscriberError {
            switch error {
            case .modelsMissing(let url): throw EngineError.modelsMissing(url)
            default: throw error
            }
        }
    }

    func transcribe(_ audio: URL) async throws -> [TranscriptSegment] {
        let result: ParakeetTranscriptResult
        do {
            result = try await transcriber.transcribe(audio)
        } catch let error as ParakeetTranscriber.TranscriberError {
            switch error {
            case .notPrepared: throw EngineError.notPrepared
            case .unreadableAudio(let url, let cause): throw EngineError.unreadableAudio(url, cause)
            case .modelsMissing(let url): throw EngineError.modelsMissing(url)
            }
        }
        let words = result.words
        guard !words.isEmpty else {
            let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty
                ? []
                : [TranscriptSegment(start: 0, end: result.durationSeconds, text: text)]
        }
        return Self.segments(from: words)
    }

    func release() async {
        await transcriber.release()
    }

    /// Group word timings into readable segments: break on sentence-ending
    /// punctuation (parakeet v2 emits punctuation), a silence gap, or a hard
    /// length cap so a run-on speaker still wraps.
    private static func segments(from words: [ParakeetTranscriptWord]) -> [TranscriptSegment] {
        var out: [TranscriptSegment] = []
        var current: [ParakeetTranscriptWord] = []

        func flush() {
            guard let first = current.first, let last = current.last else { return }
            out.append(TranscriptSegment(
                start: first.startsAtSeconds,
                end: last.endsAtSeconds,
                text: current.map(\.text).joined(separator: " ")
            ))
            current = []
        }

        for word in words {
            if let last = current.last, word.startsAtSeconds - last.endsAtSeconds > 1.0 {
                flush()
            }
            current.append(word)
            let endsSentence = word.text.hasSuffix(".")
                || word.text.hasSuffix("?")
                || word.text.hasSuffix("!")
            if endsSentence || current.count >= 60 {
                flush()
            }
        }
        flush()
        return out
    }
}
