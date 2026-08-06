import Foundation
import RecordCore

/// Loads Record's typed configuration once at process startup.
enum Config {
    static let path = RecordPaths.configurationFile(
        home: FileManager.default.homeDirectoryForCurrentUser
    )

    static let current: AppConfiguration = load()

    static func recordingsDir() -> URL? {
        guard current.recordingsDirectory != nil else { return nil }
        return RecordPaths.resolveRecordingsDirectory(
            cliOverride: nil,
            configuration: current,
            home: FileManager.default.homeDirectoryForCurrentUser
        )
    }

    static func completionHook() -> AppConfiguration.CompletionHook? {
        current.completionHook
    }

    static func transcriptionEnabled() -> Bool {
        current.transcription.enabled
    }

    static func transcriptionEngine() -> String {
        current.transcription.engine
    }

    static func transcriptionModel() -> String {
        current.transcription.model
    }

    static func micVoiceProcessing() -> Bool {
        current.micVoiceProcessing
    }

    static func resolveRoot(cliOverride: String?) -> URL {
        RecordPaths.resolveRecordingsDirectory(
            cliOverride: cliOverride,
            configuration: current,
            home: FileManager.default.homeDirectoryForCurrentUser
        )
    }

    private static func load() -> AppConfiguration {
        guard FileManager.default.fileExists(atPath: path.path) else {
            return AppConfiguration()
        }
        do {
            return try AppConfiguration.decode(Data(contentsOf: path))
        } catch {
            FileHandle.standardError.write(Data(
                "warning: invalid configuration at \(path.path): \(error) — using defaults\n".utf8
            ))
            return AppConfiguration()
        }
    }
}
