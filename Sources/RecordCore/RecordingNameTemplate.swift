import Foundation

public enum RecordingNamePlaceholder: String, CaseIterable, Sendable {
    case date
    case time
    case clipboard
    case color
    case adjective
    case animal
    case country
    case name
    case starWars
}

public enum RecordingNameWordStyle: String, Codable, CaseIterable, Sendable {
    case lowercase
    case uppercase
    case capitalized

    fileprivate func apply(to value: String) -> String {
        switch self {
        case .lowercase: value.lowercased()
        case .uppercase: value.uppercased()
        case .capitalized: value.capitalized
        }
    }
}

public struct RecordingNameValues: Equatable, Sendable {
    public var date: String
    public var time: String
    public var clipboard: String?
    public var words: [RecordingNamePlaceholder: String]

    public init(
        timestamp: Date,
        timeZone: TimeZone = .current,
        dateFormat: String = "yyyy-MM-dd",
        timeFormat: String = "HH.mm.ss",
        clipboard: String? = nil,
        words: [RecordingNamePlaceholder: String] = [:],
        wordStyle: RecordingNameWordStyle = .capitalized
    ) {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = dateFormat
        date = formatter.string(from: timestamp)
        formatter.dateFormat = timeFormat
        time = formatter.string(from: timestamp)
        self.clipboard = clipboard
        self.words = words.mapValues { wordStyle.apply(to: $0) }
    }

    fileprivate func value(for placeholder: RecordingNamePlaceholder) throws -> String {
        switch placeholder {
        case .date: date
        case .time: time
        case .clipboard: clipboard ?? ""
        case .color, .adjective, .animal, .country, .name, .starWars:
            if let value = words[placeholder] {
                value
            } else {
                throw RecordingNameTemplate.TemplateError.missingValue(placeholder)
            }
        }
    }
}

public struct RecordingNameTemplate: Equatable, Sendable {
    public let template: String
    public let maximumCharacters: Int
    public let maximumUTF8Bytes: Int

    public init(
        _ template: String,
        maximumCharacters: Int = 120,
        maximumUTF8Bytes: Int = 200
    ) {
        self.template = template
        self.maximumCharacters = maximumCharacters
        self.maximumUTF8Bytes = maximumUTF8Bytes
    }

    public var requiresClipboard: Bool {
        (try? fragments().contains { fragment in
            if case .placeholder(.clipboard) = fragment { return true }
            return false
        }) ?? false
    }

    public func render(using values: RecordingNameValues) throws -> String {
        guard maximumCharacters > 0, maximumUTF8Bytes > 0 else {
            throw TemplateError.invalidLengthLimit
        }
        var rendered = ""
        for fragment in try fragments() {
            switch fragment {
            case .literal(let value): rendered += value
            case .placeholder(let placeholder): rendered += try values.value(for: placeholder)
            }
        }
        return Self.sanitize(
            rendered,
            maximumCharacters: maximumCharacters,
            maximumUTF8Bytes: maximumUTF8Bytes
        )
    }

    public enum TemplateError: Error, Equatable {
        case malformedTemplate
        case unknownPlaceholder(String)
        case missingValue(RecordingNamePlaceholder)
        case invalidLengthLimit
    }

    private enum Fragment {
        case literal(String)
        case placeholder(RecordingNamePlaceholder)
    }

    private func fragments() throws -> [Fragment] {
        var fragments: [Fragment] = []
        var literal = ""
        var index = template.startIndex

        func flushLiteral() {
            guard !literal.isEmpty else { return }
            fragments.append(.literal(literal))
            literal = ""
        }

        while index < template.endIndex {
            let character = template[index]
            let next = template.index(after: index)
            if character == "{" {
                if next < template.endIndex, template[next] == "{" {
                    literal.append("{")
                    index = template.index(after: next)
                    continue
                }
                guard let close = template[next...].firstIndex(of: "}") else {
                    throw TemplateError.malformedTemplate
                }
                let name = String(template[next..<close])
                guard !name.isEmpty, !name.contains("{") else {
                    throw TemplateError.malformedTemplate
                }
                guard let placeholder = RecordingNamePlaceholder(rawValue: name) else {
                    throw TemplateError.unknownPlaceholder(name)
                }
                flushLiteral()
                fragments.append(.placeholder(placeholder))
                index = template.index(after: close)
            } else if character == "}" {
                guard next < template.endIndex, template[next] == "}" else {
                    throw TemplateError.malformedTemplate
                }
                literal.append("}")
                index = template.index(after: next)
            } else {
                literal.append(character)
                index = next
            }
        }
        flushLiteral()
        return fragments
    }

    private static func sanitize(
        _ value: String,
        maximumCharacters: Int,
        maximumUTF8Bytes: Int
    ) -> String {
        let forbidden = CharacterSet.controlCharacters.union(CharacterSet(charactersIn: "/:"))
        let replacedScalars = value.unicodeScalars.map { scalar -> Character in
            forbidden.contains(scalar) ? "-" : Character(String(scalar))
        }
        let normalizedWhitespace = String(replacedScalars)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        let trimmed = normalizedWhitespace.trimmingCharacters(
            in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "."))
        )
        let fallback = trimmed.isEmpty ? "Recording" : trimmed

        var output = ""
        var byteCount = 0
        for character in fallback.prefix(maximumCharacters) {
            let bytes = String(character).utf8.count
            guard byteCount + bytes <= maximumUTF8Bytes else { break }
            output.append(character)
            byteCount += bytes
        }
        let bounded = output.trimmingCharacters(
            in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "."))
        )
        if !bounded.isEmpty {
            return bounded
        }

        // Limits are positive here, so an ASCII fallback always fits at least one byte.
        return String("Recording".prefix(min(maximumCharacters, maximumUTF8Bytes)))
    }
}

public enum RecordingNameAllocator {
    public static func availableFileURL(
        in directory: URL,
        baseName: String,
        pathExtension: String,
        fileManager: FileManager = .default,
        maximumAttempts: Int = 10_000
    ) throws -> URL {
        let normalizedExtension = pathExtension.trimmingCharacters(
            in: CharacterSet(charactersIn: "."))
        guard LocalFileNamePolicy.isSafeComponent(baseName),
            !normalizedExtension.isEmpty,
            LocalFileNamePolicy.isSafeComponent(normalizedExtension),
            maximumAttempts > 0
        else {
            throw AllocationError.invalidComponent
        }

        for attempt in 1...maximumAttempts {
            let suffix = attempt == 1 ? "" : "-\(attempt)"
            let filename = "\(baseName)\(suffix).\(normalizedExtension)"
            let candidate = directory.appendingPathComponent(filename)
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        throw AllocationError.exhausted(maximumAttempts)
    }

    public enum AllocationError: Error, Equatable {
        case invalidComponent
        case exhausted(Int)
    }
}
