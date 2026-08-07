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

    /// One immutable capture interval. Segment files remain private working
    /// media until the canonical export has been assembled and validated.
    public struct CaptureSegment: Codable, Equatable, Sendable {
        public var index: Int
        public var startedAtMilliseconds: Int
        public var endedAtMilliseconds: Int?
        public var tracks: [Track]

        public init(
            index: Int,
            startedAtMilliseconds: Int,
            endedAtMilliseconds: Int? = nil,
            tracks: [Track]
        ) {
            self.index = index
            self.startedAtMilliseconds = startedAtMilliseconds
            self.endedAtMilliseconds = endedAtMilliseconds
            self.tracks = tracks
        }

        enum CodingKeys: String, CodingKey {
            case index
            case startedAtMilliseconds = "started_at_ms"
            case endedAtMilliseconds = "ended_at_ms"
            case tracks
        }
    }

    public struct CaptureEvent: Codable, Equatable, Sendable {
        public enum Kind: String, Codable, Sendable {
            case started
            case paused
            case resumed
            case stopped
        }

        public var kind: Kind
        public var occurredAtMilliseconds: Int
        public var segmentIndex: Int?

        public init(
            kind: Kind,
            occurredAtMilliseconds: Int,
            segmentIndex: Int? = nil
        ) {
            self.kind = kind
            self.occurredAtMilliseconds = occurredAtMilliseconds
            self.segmentIndex = segmentIndex
        }

        enum CodingKeys: String, CodingKey {
            case kind
            case occurredAtMilliseconds = "occurred_at_ms"
            case segmentIndex = "segment_index"
        }
    }

    public var schemaVersion: Int
    public var id: UUID
    public var state: State
    public var ownerProcessIdentifier: Int32?
    public var startedAt: Date
    public var endedAt: Date?
    public var tracks: [Track]
    public var failure: CaptureFailure?
    public var healthEvents: [CaptureHealthEvent]?
    public var captureSegments: [CaptureSegment]?
    public var captureEvents: [CaptureEvent]?

    public init(
        schemaVersion: Int = SessionManifest.currentSchemaVersion,
        id: UUID = UUID(),
        state: State = .recording,
        ownerProcessIdentifier: Int32? = nil,
        startedAt: Date,
        endedAt: Date? = nil,
        tracks: [Track],
        failure: CaptureFailure? = nil,
        healthEvents: [CaptureHealthEvent]? = nil,
        captureSegments: [CaptureSegment]? = nil,
        captureEvents: [CaptureEvent]? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.state = state
        self.ownerProcessIdentifier = ownerProcessIdentifier
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.tracks = tracks
        self.failure = failure
        self.healthEvents = healthEvents
        self.captureSegments = captureSegments
        self.captureEvents = captureEvents
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case id
        case state
        case ownerProcessIdentifier = "owner_process_id"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case tracks
        case failure
        case healthEvents = "capture_health"
        case captureSegments = "capture_segments"
        case captureEvents = "capture_events"
    }

    public func finalized(at end: Date, tracks finalizedTracks: [Track]) throws -> Self {
        guard state == .recording || state == .interrupted else {
            throw ManifestError.invalidTransition(from: state, to: .finalized)
        }
        return try transitioned(to: .finalized, at: end, tracks: finalizedTracks)
    }

    public func interrupted(at end: Date) throws -> Self {
        guard state == .recording else {
            throw ManifestError.invalidTransition(from: state, to: .interrupted)
        }
        return try transitioned(to: .interrupted, at: end, tracks: tracks)
    }

    public func failed(at end: Date) throws -> Self {
        guard state == .recording else {
            throw ManifestError.invalidTransition(from: state, to: .failed)
        }
        return try transitioned(to: .failed, at: end, tracks: tracks)
    }

    public func write(to sessionDirectory: URL) throws {
        try validate()
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
        try manifest.validate()
        return manifest
    }

    public enum ManifestError: Error, Equatable {
        case invalidTransition(from: State, to: State)
        case endBeforeStart
        case unsupportedSchema(Int)
        case unsafeTrackFilename(String)
        case duplicateTrackFilename(String)
        case invalidCaptureSegment(Int)
        case duplicateCaptureSegment(Int)
        case invalidCaptureEvent
    }

    private func transitioned(to nextState: State, at end: Date, tracks: [Track]) throws -> Self {
        guard end >= startedAt else {
            throw ManifestError.endBeforeStart
        }
        var copy = self
        copy.state = nextState
        copy.endedAt = end
        copy.tracks = tracks
        return copy
    }

    private func validate() throws {
        var filenames: Set<String> = []
        for track in tracks {
            try Self.validate(track: track, filenames: &filenames)
        }

        var segmentIndices: Set<Int> = []
        for segment in captureSegments ?? [] {
            guard segment.index > 0,
                segment.startedAtMilliseconds >= 0,
                segment.endedAtMilliseconds.map({ $0 >= segment.startedAtMilliseconds }) ?? true,
                !segment.tracks.isEmpty
            else {
                throw ManifestError.invalidCaptureSegment(segment.index)
            }
            guard segmentIndices.insert(segment.index).inserted else {
                throw ManifestError.duplicateCaptureSegment(segment.index)
            }
            for track in segment.tracks {
                try Self.validate(track: track, filenames: &filenames)
            }
        }
        for event in captureEvents ?? [] {
            guard event.occurredAtMilliseconds >= 0,
                captureSegments == nil
                    || (event.segmentIndex.map({ segmentIndices.contains($0) }) ?? true)
            else {
                throw ManifestError.invalidCaptureEvent
            }
        }
    }

    private static func validate(
        track: Track,
        filenames: inout Set<String>
    ) throws {
        guard SessionPathPolicy.isSafeRelativeFilename(track.filename) else {
            throw ManifestError.unsafeTrackFilename(track.filename)
        }
        guard filenames.insert(track.filename).inserted else {
            throw ManifestError.duplicateTrackFilename(track.filename)
        }
    }
}

public enum SessionPathPolicy {
    /// Session-owned artifacts are single relative path components. This keeps
    /// malformed manifests from escaping the session directory.
    public static func isSafeRelativeFilename(_ filename: String) -> Bool {
        !filename.isEmpty
            && filename != "."
            && filename != ".."
            && !filename.hasPrefix("/")
            && !filename.contains("/")
            && !filename.contains("\0")
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
