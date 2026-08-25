import Foundation

/// Canonical, engine-neutral transcript representation.
public struct TranscriptDocument: Codable, Equatable, Sendable {
    public struct Segment: Codable, Equatable, Sendable {
        public let speaker: String
        public let startMilliseconds: Int
        public let endMilliseconds: Int
        public let text: String
        public let overlapGroup: String?

        public init(
            speaker: String,
            startMilliseconds: Int,
            endMilliseconds: Int,
            text: String,
            overlapGroup: String? = nil
        ) {
            self.speaker = speaker
            self.startMilliseconds = startMilliseconds
            self.endMilliseconds = endMilliseconds
            self.text = text
            self.overlapGroup = overlapGroup
        }

        enum CodingKeys: String, CodingKey {
            case speaker
            case startMilliseconds = "start_ms"
            case endMilliseconds = "end_ms"
            case text
            case overlapGroup = "overlap_group"
        }
    }

    public let engine: String
    public let model: String
    public let createdAt: String
    public let segments: [Segment]

    public init(engine: String, model: String, createdAt: String, segments: [Segment]) {
        self.engine = engine
        self.model = model
        self.createdAt = createdAt
        self.segments = segments
    }

    enum CodingKeys: String, CodingKey {
        case engine
        case model
        case createdAt = "created_at"
        case segments
    }

    /// Writes the readable derivative first and the canonical JSON completion
    /// marker last. A session is pending whenever `transcript.json` is absent.
    public func write(to sessionDirectory: URL, title: String) throws {
        try Data(rendered(title: title).utf8).write(
            to: sessionDirectory.appendingPathComponent("transcript.md"),
            options: .atomic
        )

        try encodedData(prettyPrinted: true).write(
            to: sessionDirectory.appendingPathComponent("transcript.json"),
            options: .atomic
        )
    }

    /// Writes an engine-neutral JSON sidecar without creating the canonical
    /// completion marker. Used to preserve unsuppressed ASR segments whenever
    /// the readable transcript removes high-confidence speaker echo.
    public func writeJSON(to url: URL) throws {
        try encodedData(prettyPrinted: true).write(to: url, options: .atomic)
    }

    /// Stable source bytes for binding a refinement report to the exact local
    /// transcript it reviewed. This does not write another artifact.
    public func canonicalData() throws -> Data {
        try encodedData(prettyPrinted: false)
    }

    public func rendered(title: String) -> String {
        var lines = ["# \(title)", "", "engine: \(engine) (\(model))", ""]
        for segment in segments {
            let overlap = segment.overlapGroup == nil ? "" : " (overlapping)"
            lines.append(
                "**[\(Self.clock(segment.startMilliseconds))] \(segment.speaker)\(overlap):** \(segment.text)"
            )
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private func encodedData(prettyPrinted: Bool) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        if prettyPrinted {
            encoder.outputFormatting.insert(.prettyPrinted)
        }
        return try encoder.encode(self)
    }

    private static func clock(_ milliseconds: Int) -> String {
        let total = milliseconds / 1_000
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }
}
