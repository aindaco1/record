import Foundation

public struct RecordingNameTemplate: Equatable, Sendable {
    public static let defaultValue = try! RecordingNameTemplate(
        validating: "{date} at {time} - {color} {animal}"
    )
    public static let legacyValue = try! RecordingNameTemplate(
        validating: "Record {date} {time}"
    )
    public static let maximumTemplateLength = 512
    public static let maximumRenderedLength = LocalFileNamePolicy.maximumCharacters
    public static let maximumRenderedUTF8Bytes = LocalFileNamePolicy.maximumUTF8Bytes

    public let rawValue: String

    private let components: [Component]

    public init(validating rawValue: String) throws {
        guard !rawValue.isEmpty, rawValue.count <= Self.maximumTemplateLength else {
            throw TemplateError.invalidLength
        }
        let components = try Self.parse(rawValue)
        guard components.contains(where: { !$0.isEmpty }) else {
            throw TemplateError.emptyOutput
        }
        self.rawValue = rawValue
        self.components = components
    }

    public var requiresClipboard: Bool {
        components.contains(.token(.clipboard))
    }

    public func render(
        at date: Date,
        timeZone: TimeZone = .current,
        clipboard: String? = nil,
        wordSeed: UInt64 = 0
    ) -> String {
        let dateFormatter = Self.formatter("yyyy-MM-dd", timeZone: timeZone)
        let timeFormatter = Self.formatter("HH.mm.ss", timeZone: timeZone)
        var wordOffset: UInt64 = 0
        let rendered = components.map { component in
            switch component {
            case .literal(let value):
                return value
            case .token(let token):
                switch token {
                case .date: return dateFormatter.string(from: date)
                case .time: return timeFormatter.string(from: date)
                case .clipboard: return clipboard ?? ""
                case .color, .adjective, .animal, .country, .name, .starWars:
                    defer { wordOffset &+= 1 }
                    let words = token.words
                    let mixedSeed = wordSeed &+ wordOffset &* 0x9E37_79B9_7F4A_7C15
                    return words[Int(mixedSeed % UInt64(words.count))]
                }
            }
        }.joined()
        return Self.sanitize(rendered)
    }

    public enum TemplateError: Error, Equatable, Sendable {
        case invalidLength
        case unknownToken(String)
        case unmatchedBrace
        case emptyOutput
    }

    private enum Component: Equatable, Sendable {
        case literal(String)
        case token(Token)

        var isEmpty: Bool {
            if case .literal(let value) = self { return value.isEmpty }
            return false
        }
    }

    private enum Token: String, Equatable, Sendable {
        case date
        case time
        case clipboard
        case color
        case adjective
        case animal
        case country
        case name
        case starWars

        var words: [String] {
            switch self {
            case .color: ["Amber", "Blue", "Coral", "Green", "Indigo", "Violet"]
            case .adjective: ["Bright", "Calm", "Clever", "Quick", "Quiet", "Warm"]
            case .animal: ["Badger", "Falcon", "Fox", "Otter", "Raven", "Tiger"]
            case .country: ["Canada", "Iceland", "Japan", "Kenya", "Norway", "Peru"]
            case .name: ["Alex", "Jordan", "Morgan", "Riley", "Sam", "Taylor"]
            case .starWars: ["Ahsoka", "Chewbacca", "Leia", "Luke", "Rey", "Yoda"]
            case .date, .time, .clipboard:
                preconditionFailure("non-word token has no dictionary")
            }
        }
    }

    private static func parse(_ value: String) throws -> [Component] {
        var components: [Component] = []
        var literal = ""
        var index = value.startIndex

        func flushLiteral() {
            guard !literal.isEmpty else { return }
            components.append(.literal(literal))
            literal.removeAll(keepingCapacity: true)
        }

        while index < value.endIndex {
            let next = value.index(after: index)
            let character = value[index]
            if character == "{", next < value.endIndex, value[next] == "{" {
                literal.append("{")
                index = value.index(after: next)
                continue
            }
            if character == "}", next < value.endIndex, value[next] == "}" {
                literal.append("}")
                index = value.index(after: next)
                continue
            }
            if character == "}" {
                throw TemplateError.unmatchedBrace
            }
            guard character == "{" else {
                literal.append(character)
                index = next
                continue
            }

            guard let closing = value[next...].firstIndex(of: "}") else {
                throw TemplateError.unmatchedBrace
            }
            let rawToken = String(value[next..<closing])
            guard let token = Token(rawValue: rawToken) else {
                throw TemplateError.unknownToken(rawToken)
            }
            flushLiteral()
            components.append(.token(token))
            index = value.index(after: closing)
        }
        flushLiteral()
        return components
    }

    private static func formatter(_ format: String, timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = format
        return formatter
    }

    private static func sanitize(_ value: String) -> String {
        let disallowed = CharacterSet.controlCharacters.union(
            CharacterSet(charactersIn: "/:")
        )
        let scalars = value.precomposedStringWithCanonicalMapping.unicodeScalars.map {
            disallowed.contains($0) ? " " : String($0)
        }.joined()
        let collapsed = scalars.split(whereSeparator: { $0.isWhitespace })
            .filter { $0 != "." && $0 != ".." }
            .joined(separator: " ")
        let trimmed = collapsed.trimmingCharacters(
            in: .whitespacesAndNewlines.union(
                CharacterSet(charactersIn: ".")
            ))
        let bounded = LocalFileNamePolicy.boundedPrefix(of: trimmed)
            .trimmingCharacters(
                in: .whitespacesAndNewlines.union(
                    CharacterSet(charactersIn: ".")
                ))
        return bounded.isEmpty ? "Record" : bounded
    }
}
