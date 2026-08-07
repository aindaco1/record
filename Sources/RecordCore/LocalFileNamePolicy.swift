import Foundation

/// Shared limits for locally exported recording names. The byte cap leaves
/// room for collision suffixes and the file extension under APFS's 255-byte
/// component limit, including when a template contains multibyte Unicode.
public enum LocalFileNamePolicy {
    public static let maximumCharacters = 120
    public static let maximumUTF8Bytes = 200

    public static func isSafeComponent(_ component: String) -> Bool {
        !component.isEmpty
            && component.count <= maximumCharacters
            && component.utf8.count <= maximumUTF8Bytes
            && component != "."
            && component != ".."
            && !component.hasPrefix("/")
            && !component.contains("/")
            && !component.contains(":")
            && component.unicodeScalars.allSatisfy {
                !CharacterSet.controlCharacters.contains($0)
            }
    }

    public static func boundedPrefix(of value: String) -> String {
        var result = ""
        var byteCount = 0
        for character in value.prefix(maximumCharacters) {
            let characterBytes = String(character).utf8.count
            guard byteCount + characterBytes <= maximumUTF8Bytes else { break }
            result.append(character)
            byteCount += characterBytes
        }
        return result
    }
}
