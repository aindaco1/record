import Foundation

/// Local, resumable work beside the session, never a second history database.
/// Successful raw ASR spans survive failure of the other source or cleanup.
public struct TranscriptionCheckpoint: Codable, Equatable, Sendable {
    public static let filename = "transcription.state.json"
    public enum State: String, Codable, Sendable {
        case pending, processing, needsRetry, deferred, complete
        public var title: String {
            switch self {
            case .pending: "Queued"
            case .processing: "Transcribing"
            case .needsRetry: "Needs retry"
            case .deferred: "Deferred"
            case .complete: "Ready"
            }
        }
    }
    public struct Source: Codable, Equatable, Sendable {
        public let filename: String
        public let speaker: String
        public let offsetMilliseconds: Int
        public let byteCount: UInt64
        public let modifiedAt: Date

        public init(
            filename: String, speaker: String, offsetMilliseconds: Int,
            byteCount: UInt64, modifiedAt: Date
        ) {
            self.filename = filename
            self.speaker = speaker
            self.offsetMilliseconds = offsetMilliseconds
            self.byteCount = byteCount
            self.modifiedAt = modifiedAt
        }
    }
    public struct Track: Codable, Equatable, Sendable {
        public let source: Source
        /// nil means unfinished; [] means successfully recognized silence.
        public var segments: [TranscriptDocument.Segment]?
        public init(source: Source, segments: [TranscriptDocument.Segment]? = nil) {
            self.source = source
            self.segments = segments
        }
    }

    public let schemaVersion: Int
    public let engine: String
    public let model: String
    public let language: String
    public var state: State
    public var tracks: [Track]
    public var completedTracks: Int { tracks.filter { $0.segments != nil }.count }
    public var isPartial: Bool { completedTracks > 0 && completedTracks < tracks.count }

    public init(
        engine: String, model: String, language: String,
        state: State = .pending, tracks: [Track]
    ) {
        schemaVersion = 1
        self.engine = engine
        self.model = model
        self.language = language
        self.state = state
        self.tracks = tracks
    }

    /// Reuse only an unchanged source with the same recognition settings.
    public func cachedSegments(
        for source: Source, engine: String, model: String,
        language: String
    ) -> [TranscriptDocument.Segment]? {
        guard self.engine == engine, self.model == model, self.language == language else {
            return nil
        }
        return tracks.first { $0.source == source }?.segments
    }

    public func write(to directory: URL) throws {
        try validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(self).write(
            to: directory.appendingPathComponent(Self.filename), options: .atomic)
    }

    public static func read(from directory: URL) throws -> Self {
        let url = directory.appendingPathComponent(filename)
        guard let size = LocalFilePolicy.regularFileSize(at: url), size <= 32 * 1_024 * 1_024
        else { throw CheckpointError.invalid }
        let value = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        try value.validate()
        return value
    }

    private func validate() throws {
        guard schemaVersion == 1, tracks.count <= 2,
            Set(tracks.map { $0.source.filename }).count == tracks.count,
            tracks.allSatisfy({ SessionPathPolicy.isSafeRelativeFilename($0.source.filename) }),
            state != .complete || completedTracks == tracks.count
        else { throw CheckpointError.invalid }
    }

    public enum CheckpointError: Error { case invalid }
}
