import Foundation

/// Canonical, crash-recoverable session state. `session.json` is written when
/// a session directory is created and atomically replaced at each transition.
public struct SessionManifest: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public enum State: String, Codable, Sendable {
        case recording
        case finalized
        case interrupted
        case failed
    }

    public enum TrackKind: String, Codable, Sendable {
        case microphone
        case systemAudio = "system_audio"
        case screen
        case camera
    }

    public struct Track: Codable, Equatable, Sendable {
        public var kind: TrackKind
        public var filename: String
        public var speaker: String?
        public var startOffsetMilliseconds: Int

        public init(
            kind: TrackKind,
            filename: String,
            speaker: String? = nil,
            startOffsetMilliseconds: Int = 0
        ) {
            self.kind = kind
            self.filename = filename
            self.speaker = speaker
            self.startOffsetMilliseconds = startOffsetMilliseconds
        }

        enum CodingKeys: String, CodingKey {
            case kind
            case filename
            case speaker
            case startOffsetMilliseconds = "start_offset_ms"
        }
    }

    public var schemaVersion: Int
    public var id: UUID
    public var state: State
    public var startedAt: Date
    public var endedAt: Date?
    public var tracks: [Track]

    public init(
        schemaVersion: Int = SessionManifest.currentSchemaVersion,
        id: UUID = UUID(),
        state: State = .recording,
        startedAt: Date,
        endedAt: Date? = nil,
        tracks: [Track]
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.state = state
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.tracks = tracks
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case id
        case state
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case tracks
    }

    public func finalized(at end: Date, tracks finalizedTracks: [Track]) throws -> Self {
        guard state == .recording else {
            throw ManifestError.invalidTransition(from: state, to: .finalized)
        }
        guard end >= startedAt else {
            throw ManifestError.endBeforeStart
        }
        var copy = self
        copy.state = .finalized
        copy.endedAt = end
        copy.tracks = finalizedTracks
        return copy
    }

    public func write(to sessionDirectory: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(self).write(
            to: sessionDirectory.appendingPathComponent("session.json"),
            options: .atomic
        )
    }

    public static func read(from sessionDirectory: URL) throws -> Self {
        let data = try Data(
            contentsOf: sessionDirectory.appendingPathComponent("session.json")
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(Self.self, from: data)
        guard manifest.schemaVersion == currentSchemaVersion else {
            throw ManifestError.unsupportedSchema(manifest.schemaVersion)
        }
        return manifest
    }

    public enum ManifestError: Error, Equatable {
        case invalidTransition(from: State, to: State)
        case endBeforeStart
        case unsupportedSchema(Int)
    }
}

public enum SessionFolderAllocator {
    public static func createDirectory(
        under root: URL,
        startedAt: Date,
        timeZone: TimeZone = .current,
        fileManager: FileManager = .default
    ) throws -> URL {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy.MM.dd-HHmm"

        let base = formatter.string(from: startedAt)
        var candidate = root.appendingPathComponent(base, isDirectory: true)
        var suffix = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = root.appendingPathComponent("\(base)-\(suffix)", isDirectory: true)
            suffix += 1
        }
        try fileManager.createDirectory(at: candidate, withIntermediateDirectories: true)
        return candidate
    }
}
