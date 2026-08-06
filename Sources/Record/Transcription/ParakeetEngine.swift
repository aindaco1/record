import AVFoundation
import FluidAudio
import Foundation
import RecordCore

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

    private let version: AsrModelVersion
    private var manager: AsrManager?

    init(selection: ParakeetModelID) {
        model = selection.rawValue
        switch selection {
        case .v2: version = .v2
        case .v3: version = .v3
        }
    }

    func prepare() async throws {
        FluidAudioOfflinePolicy.enforce()
        guard manager == nil else { return }
        let cache = AsrModels.defaultCacheDirectory(for: version)
        guard AsrModels.modelsExist(at: cache, version: version) else {
            throw EngineError.modelsMissing(cache)
        }
        let models = try await AsrModels.load(from: cache, version: version)
        let manager = AsrManager()
        try await manager.loadModels(models)
        self.manager = manager
    }

    func transcribe(_ audio: URL) async throws -> [TranscriptSegment] {
        guard let manager else { throw EngineError.notPrepared }

        // A track with no frames (recorder died before its first buffer)
        // makes AVFoundation raise an ObjC exception deep inside the
        // resampler — uncatchable from Swift, so it takes the whole daemon
        // down. Check readability up front instead.
        do {
            let probe = try AVAudioFile(forReading: audio)
            guard probe.length > 0 else { throw EngineError.unreadableAudio(audio, nil) }
        } catch let error as EngineError {
            throw error
        } catch {
            throw EngineError.unreadableAudio(audio, error)
        }

        var state = try TdtDecoderState()
        let result = try await manager.transcribe(audio, decoderState: &state)

        let words = buildWordTimings(from: result.tokenTimings ?? [])
        guard !words.isEmpty else {
            let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty
                ? []
                : [TranscriptSegment(start: 0, end: result.duration, text: text)]
        }
        return Self.segments(from: words)
    }

    func release() async {
        if let manager { await manager.cleanup() }
        manager = nil
    }

    /// Group word timings into readable segments: break on sentence-ending
    /// punctuation (parakeet v2 emits punctuation), a silence gap, or a hard
    /// length cap so a run-on speaker still wraps.
    private static func segments(from words: [WordTiming]) -> [TranscriptSegment] {
        var out: [TranscriptSegment] = []
        var current: [WordTiming] = []

        func flush() {
            guard let first = current.first, let last = current.last else { return }
            out.append(TranscriptSegment(
                start: first.startTime,
                end: last.endTime,
                text: current.map(\.word).joined(separator: " ")
            ))
            current = []
        }

        for word in words {
            if let last = current.last, word.startTime - last.endTime > 1.0 {
                flush()
            }
            current.append(word)
            let endsSentence = word.word.hasSuffix(".")
                || word.word.hasSuffix("?")
                || word.word.hasSuffix("!")
            if endsSentence || current.count >= 60 {
                flush()
            }
        }
        flush()
        return out
    }
}
