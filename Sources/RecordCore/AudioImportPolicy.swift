import Foundation

public enum AudioImportPolicy {
    public static let extensions: Set<String> = ["wav", "mp3", "m4a", "aif", "aiff", "caf", "flac"]
    public static let maximumBytes: UInt64 = 4 * 1_024 * 1_024 * 1_024
    public static let maximumDurationSeconds: Double = 12 * 60 * 60

    public enum ImportError: Error, LocalizedError {
        case unsupportedFile, invalidAudio, sourceChanged, invalidDestination
        public var errorDescription: String? {
            switch self {
            case .unsupportedFile:
                L10n.text(
                    "Choose a regular WAV, MP3, M4A, AIFF, CAF, or FLAC audio file under 4 GB.")
            case .invalidAudio:
                L10n.text(
                    "The audio file could not be decoded completely, is empty, or is longer than 12 hours."
                )
            case .sourceChanged:
                L10n.text(
                    "The source file changed during import. Wait until it finishes saving, then try again."
                )
            case .invalidDestination:
                L10n.text("Choose an available save folder before importing audio.")
            }
        }
    }

    public static func sessionName(for source: URL, id: UUID) -> String {
        let base = source.deletingPathExtension().lastPathComponent.map { character in
            character == ":"
                || character.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
                ? Character("_") : character
        }
        return "Import-" + LocalFileNamePolicy.boundedPrefix(of: String(base)) + "-"
            + id.uuidString.prefix(8)
    }
}
