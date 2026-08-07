import AVFoundation
import FluidAudio
import Foundation
import RecordCore

public enum RecordFluidAudioOfflinePolicy {
    public static func enforce() {
        ModelHub.offlineMode = true
    }

    public static var isEnforced: Bool { ModelHub.offlineMode }
}

public struct ParakeetTranscriptToken: Codable, Sendable, Equatable {
    public let text: String
    public let tokenId: Int
    public let startsAtSeconds: TimeInterval
    public let endsAtSeconds: TimeInterval
    public let confidence: Float

    public init(
        text: String,
        tokenId: Int,
        startsAtSeconds: TimeInterval,
        endsAtSeconds: TimeInterval,
        confidence: Float
    ) {
        self.text = text
        self.tokenId = tokenId
        self.startsAtSeconds = startsAtSeconds
        self.endsAtSeconds = endsAtSeconds
        self.confidence = confidence
    }
}

public struct ParakeetTranscriptWord: Codable, Sendable, Equatable {
    public let text: String
    public let startsAtSeconds: TimeInterval
    public let endsAtSeconds: TimeInterval

    public init(text: String, startsAtSeconds: TimeInterval, endsAtSeconds: TimeInterval) {
        self.text = text
        self.startsAtSeconds = startsAtSeconds
        self.endsAtSeconds = endsAtSeconds
    }
}

public struct ParakeetTranscriptResult: Codable, Sendable, Equatable {
    public let text: String
    public let durationSeconds: TimeInterval
    public let confidence: Float
    public let tokens: [ParakeetTranscriptToken]
    public let words: [ParakeetTranscriptWord]

    public init(
        text: String,
        durationSeconds: TimeInterval,
        confidence: Float,
        tokens: [ParakeetTranscriptToken],
        words: [ParakeetTranscriptWord]
    ) {
        self.text = text
        self.durationSeconds = durationSeconds
        self.confidence = confidence
        self.tokens = tokens
        self.words = words
    }
}

public actor ParakeetTranscriber {
    public enum TranscriberError: Error, CustomStringConvertible {
        case notPrepared
        case unreadableAudio(URL, Error?)
        case modelsMissing(URL)

        public var description: String {
            switch self {
            case .notPrepared: "parakeet transcriber used before prepare()"
            case .unreadableAudio(let url, let error):
                "unreadable or empty audio \(url.lastPathComponent)"
                    + (error.map { ": \($0)" } ?? "")
            case .modelsMissing(let url): "local transcription model is missing at \(url.path)"
            }
        }
    }

    public nonisolated let model: ParakeetModelID
    private let version: AsrModelVersion
    private var manager: AsrManager?

    public init(model: ParakeetModelID = .v3) {
        self.model = model
        version = model == .v2 ? .v2 : .v3
    }

    public static func defaultModelDirectory(for model: ParakeetModelID = .v3) -> URL {
        AsrModels.defaultCacheDirectory(for: model == .v2 ? .v2 : .v3)
    }

    public func prepare(modelDirectory: URL? = nil) async throws {
        RecordFluidAudioOfflinePolicy.enforce()
        guard manager == nil else { return }
        let directory = modelDirectory ?? Self.defaultModelDirectory(for: model)
        guard AsrModels.modelsExist(at: directory, version: version) else {
            throw TranscriberError.modelsMissing(directory)
        }
        let models = try await AsrModels.load(from: directory, version: version)
        let manager = AsrManager()
        try await manager.loadModels(models)
        self.manager = manager
    }

    public func transcribe(_ audio: URL) async throws -> ParakeetTranscriptResult {
        guard let manager else { throw TranscriberError.notPrepared }
        let audioDuration: TimeInterval
        do {
            let probe = try AVAudioFile(forReading: audio)
            guard probe.length > 0 else { throw TranscriberError.unreadableAudio(audio, nil) }
            audioDuration = TimeInterval(probe.length) / probe.fileFormat.sampleRate
        } catch let error as TranscriberError {
            throw error
        } catch {
            throw TranscriberError.unreadableAudio(audio, error)
        }

        var state = try TdtDecoderState()
        let result = try await manager.transcribe(audio, decoderState: &state)
        let tokenTimings = result.tokenTimings ?? []
        return ParakeetTranscriptResult(
            text: result.text,
            durationSeconds: Self.resolvedDuration(reported: result.duration, audio: audioDuration),
            confidence: result.confidence,
            tokens: tokenTimings.map {
                ParakeetTranscriptToken(
                    text: $0.token,
                    tokenId: $0.tokenId,
                    startsAtSeconds: $0.startTime,
                    endsAtSeconds: $0.endTime,
                    confidence: $0.confidence
                )
            },
            words: buildWordTimings(from: tokenTimings).map {
                ParakeetTranscriptWord(
                    text: $0.word,
                    startsAtSeconds: $0.startTime,
                    endsAtSeconds: $0.endTime
                )
            }
        )
    }

    public func release() async {
        if let manager { await manager.cleanup() }
        manager = nil
    }

    static func resolvedDuration(reported: TimeInterval, audio: TimeInterval) -> TimeInterval {
        reported > 0 ? reported : audio
    }
}
