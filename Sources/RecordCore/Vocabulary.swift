import CryptoKit
import Foundation

/// Explicit local spelling preferences. No phonetic or fuzzy rewriting.
public struct Vocabulary: Codable, Equatable, Sendable {
    public struct Term: Codable, Equatable, Identifiable, Sendable {
        public var id: UUID
        public var preferred: String
        public var aliases: [String]

        public init(id: UUID = UUID(), preferred: String, aliases: [String] = []) {
            self.id = id
            self.preferred = preferred
            self.aliases = aliases
        }
    }

    public var terms: [Term]
    public init(terms: [Term] = []) { self.terms = terms }

    public enum ValidationError: Error, Equatable {
        case tooManyTerms, invalidTerm, conflictingAlias
    }

    public func validate() throws {
        guard terms.count <= 200 else { throw ValidationError.tooManyTerms }
        var owners: [String: UUID] = [:]
        guard Set(terms.map(\.id)).count == terms.count else { throw ValidationError.invalidTerm }
        for term in terms {
            guard term.aliases.count <= 20 else { throw ValidationError.invalidTerm }
            for value in [term.preferred] + term.aliases {
                guard !value.isEmpty, value.count <= 128,
                    value == value.trimmingCharacters(in: .whitespacesAndNewlines),
                    value.rangeOfCharacter(from: .letters) != nil,
                    value.rangeOfCharacter(from: .controlCharacters) == nil
                else { throw ValidationError.invalidTerm }
                let key = value.precomposedStringWithCanonicalMapping.lowercased()
                    .filter { !$0.isWhitespace && $0 != "-" }
                if let owner = owners[key], owner != term.id {
                    throw ValidationError.conflictingAlias
                }
                owners[key] = term.id
            }
        }
    }

    public struct Change: Codable, Equatable, Sendable {
        public let segmentIndex: Int
        public let before: String
        public let after: String
    }

    public struct Result: Sendable {
        public let transcript: TranscriptDocument
        public let changes: [Change]
    }

    public func apply(to source: TranscriptDocument) throws -> Result {
        try validate()
        let patterns = try terms.flatMap { term in
            try ([term.preferred] + term.aliases).map { spelling in
                let words = spelling.precomposedStringWithCanonicalMapping
                    .split(whereSeparator: { $0.isWhitespace || $0 == "-" })
                let pattern = words.map { NSRegularExpression.escapedPattern(for: String($0)) }
                    .joined(separator: "[\\s-]*")
                return (
                    try NSRegularExpression(
                        pattern: "(?<![\\p{L}\\p{N}\\p{M}_])" + pattern
                            + "(?![\\p{L}\\p{N}\\p{M}_])",
                        options: .caseInsensitive), term.preferred
                )
            }
        }
        let code = try NSRegularExpression(pattern: "(`+)[\\s\\S]*?\\1")
        var changes: [Change] = []
        let segments = source.segments.enumerated().map { index, segment in
            let text = segment.text
            let fullRange = NSRange(text.startIndex..., in: text)
            // Inline/fenced code is verbatim, even when it contains a glossary term.
            let codeRanges = code.matches(in: text, range: fullRange).map(\.range)
            var matches: [(NSRange, String)] = []
            for (regex, replacement) in patterns {
                for match in regex.matches(in: text, range: fullRange) {
                    if !codeRanges.contains(where: {
                        NSIntersectionRange($0, match.range).length > 0
                    }) {
                        matches.append((match.range, replacement))
                    }
                }
            }
            matches.sort {
                $0.0.location == $1.0.location
                    ? $0.0.length > $1.0.length : $0.0.location < $1.0.location
            }
            var accepted: [(NSRange, String)] = []
            var end = 0
            for match in matches where match.0.location >= end {
                accepted.append(match)
                end = NSMaxRange(match.0)
            }
            let result = NSMutableString(string: text)
            for (range, replacement) in accepted.reversed() {
                result.replaceCharacters(in: range, with: replacement)
            }
            let output = result as String
            // Do not normalize unrelated text when no spelling actually changed.
            guard output != text else { return segment }
            changes.append(Change(segmentIndex: index, before: segment.text, after: output))
            return TranscriptDocument.Segment(
                speaker: segment.speaker, startMilliseconds: segment.startMilliseconds,
                endMilliseconds: segment.endMilliseconds, text: output,
                overlapGroup: segment.overlapGroup)
        }
        return Result(
            transcript: TranscriptDocument(
                engine: source.engine, model: source.model, createdAt: source.createdAt,
                segments: segments, incompleteTrackCount: source.incompleteTrackCount),
            changes: changes)
    }
}

/// Canonical output may apply vocabulary; both raw ASR and pre-vocabulary cleanup stay intact.
public enum TranscriptVocabulary {
    public static let cleanFilename = "transcript.cleaned.json"
    public static let reportFilename = "transcript.vocabulary.json"

    public struct Report: Codable, Sendable {
        public let schemaVersion: Int
        public let sourceSHA256: String
        public let changes: [Vocabulary.Change]
    }

    public static func write(source: TranscriptDocument, vocabulary: Vocabulary, to directory: URL)
        throws
    {
        let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        for filename in [cleanFilename, reportFilename, "transcript.json", "transcript.md"] {
            let url = directory.appendingPathComponent(filename)
            if let values = try? url.resourceValues(forKeys: [
                .isRegularFileKey, .isSymbolicLinkKey,
            ]),
                values.isSymbolicLink == true || values.isRegularFile != true
            {
                throw CocoaError(.fileWriteInvalidFileName)
            }
        }
        let result = try vocabulary.apply(to: source)
        // Preserve the exact pre-vocabulary source before publishing a changed canonical output.
        try source.writeJSON(to: directory.appendingPathComponent(cleanFilename))
        let report = Report(
            schemaVersion: 1,
            sourceSHA256: SHA256.hash(data: try source.canonicalData()).map {
                String(format: "%02x", $0)
            }.joined(),
            changes: result.changes)
        try JSONEncoder().encode(report).write(
            to: directory.appendingPathComponent(reportFilename), options: .atomic)
        try result.transcript.write(to: directory, title: directory.lastPathComponent)
    }

    public static func reapply(vocabulary: Vocabulary, to directory: URL) throws {
        if let checkpoint = try? TranscriptionCheckpoint.read(from: directory),
            checkpoint.state == .processing
        {
            throw CocoaError(.fileWriteFileExists)
        }
        let clean = directory.appendingPathComponent(cleanFilename)
        let source =
            FileManager.default.fileExists(atPath: clean.path)
            ? clean : directory.appendingPathComponent("transcript.json")
        guard let size = LocalFilePolicy.regularFileSize(at: source), size <= 8 * 1_024 * 1_024,
            source.resolvingSymlinksInPath().deletingLastPathComponent()
                == directory.resolvingSymlinksInPath()
        else { throw CocoaError(.fileReadCorruptFile) }
        let transcript = try JSONDecoder().decode(
            TranscriptDocument.self, from: Data(contentsOf: source))
        try write(source: transcript, vocabulary: vocabulary, to: directory)
    }
}
