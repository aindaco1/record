@preconcurrency import FluidAudio
import Foundation

// FluidAudio's offline manager owns immutable model handles after initialize
// and is serialized by OfflineSpeakerDiarizer below. Upstream does not yet
// declare that usage Sendable, so this narrow adapter supplies the contract.
extension OfflineDiarizerManager: @retroactive @unchecked Sendable {}

public struct AnonymousSpeakerTurn: Codable, Sendable, Equatable {
    public let cluster: String
    public let startsAtSeconds: TimeInterval
    public let endsAtSeconds: TimeInterval
    public let confidence: Float

    public init(
        cluster: String,
        startsAtSeconds: TimeInterval,
        endsAtSeconds: TimeInterval,
        confidence: Float
    ) {
        self.cluster = cluster
        self.startsAtSeconds = startsAtSeconds
        self.endsAtSeconds = endsAtSeconds
        self.confidence = confidence
    }
}

public actor OfflineSpeakerDiarizer {
    public enum DiarizerError: Error, CustomStringConvertible {
        case notPrepared
        case tooManySpeakers(Int)

        public var description: String {
            switch self {
            case .notPrepared: "offline speaker diarizer used before prepare()"
            case .tooManySpeakers(let count): "offline diarizer found \(count) speakers"
            }
        }
    }

    private let maximumSpeakers: Int
    private var manager: OfflineDiarizerManager?

    public init(maximumSpeakers: Int = 6) {
        precondition((1...6).contains(maximumSpeakers))
        self.maximumSpeakers = maximumSpeakers
    }

    public static func defaultModelDirectory() -> URL {
        OfflineDiarizerModels.defaultModelsDirectory()
    }

    public func prepare(modelDirectory: URL? = nil) async throws {
        RecordFluidAudioOfflinePolicy.enforce()
        guard manager == nil else { return }
        let directory = modelDirectory ?? Self.defaultModelDirectory()
        let models = try await OfflineDiarizerModels.load(from: directory)
        let manager = OfflineDiarizerManager(
            config: OfflineDiarizerConfig.default.withSpeakers(min: 1, max: maximumSpeakers)
        )
        manager.initialize(models: models)
        self.manager = manager
    }

    public func diarize(_ audio: URL) async throws -> [AnonymousSpeakerTurn] {
        guard let manager else { throw DiarizerError.notPrepared }
        let result = try await manager.process(audio)
        let speakerCount = Set(result.segments.map(\.speakerId)).count
        guard speakerCount <= maximumSpeakers else { throw DiarizerError.tooManySpeakers(speakerCount) }
        return result.segments.map {
            AnonymousSpeakerTurn(
                cluster: $0.speakerId,
                startsAtSeconds: TimeInterval($0.startTimeSeconds),
                endsAtSeconds: TimeInterval($0.endTimeSeconds),
                confidence: $0.qualityScore
            )
        }
    }
}
