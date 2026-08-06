import Foundation

/// Record's versioned, local-only configuration.
///
/// Configuration is decoded once at launch. Keeping this model typed prevents
/// misspelled keys and type mismatches from being silently ignored.
public struct AppConfiguration: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public struct Transcription: Codable, Equatable, Sendable {
        public var enabled: Bool
        public var engine: String
        public var model: String?
        public var executable: String?
        public var language: String

        public init(
            enabled: Bool = true,
            engine: String = "parakeet",
            model: String? = "parakeet-tdt-0.6b-v3-coreml",
            executable: String? = nil,
            language: String = "auto"
        ) {
            self.enabled = enabled
            self.engine = engine
            self.model = model
            self.executable = executable
            self.language = language
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
            engine = (try container.decodeIfPresent(String.self, forKey: .engine) ?? "parakeet")
                .lowercased()
            model = try container.decodeIfPresent(String.self, forKey: .model)
            if model == nil, engine == "parakeet" {
                model = "parakeet-tdt-0.6b-v3-coreml"
            }
            executable = try container.decodeIfPresent(String.self, forKey: .executable)
            language = (try container.decodeIfPresent(String.self, forKey: .language) ?? "auto")
                .lowercased()
        }

        private enum CodingKeys: String, CodingKey {
            case enabled
            case engine
            case model
            case executable
            case language
        }
    }

    /// A post-processing hook without shell evaluation. `{session}` in an
    /// argument expands to the completed session directory.
    public struct CompletionHook: Codable, Equatable, Sendable {
        public var executable: String
        public var arguments: [String]

        public init(executable: String, arguments: [String] = ["{session}"]) {
            self.executable = executable
            self.arguments = arguments
        }
    }

    public var schemaVersion: Int
    public var recordingsDirectory: String?
    public var transcription: Transcription
    public var micVoiceProcessing: Bool
    public var completionHook: CompletionHook?

    public init(
        schemaVersion: Int = AppConfiguration.currentSchemaVersion,
        recordingsDirectory: String? = nil,
        transcription: Transcription = .init(),
        micVoiceProcessing: Bool = false,
        completionHook: CompletionHook? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.recordingsDirectory = recordingsDirectory
        self.transcription = transcription
        self.micVoiceProcessing = micVoiceProcessing
        self.completionHook = completionHook
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case recordingsDirectory = "recordings_directory"
        case transcription
        case micVoiceProcessing = "mic_voice_processing"
        case completionHook = "completion_hook"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion =
            try container.decodeIfPresent(Int.self, forKey: .schemaVersion)
            ?? Self.currentSchemaVersion
        recordingsDirectory = try container.decodeIfPresent(
            String.self,
            forKey: .recordingsDirectory
        )
        transcription =
            try container.decodeIfPresent(
                Transcription.self,
                forKey: .transcription
            ) ?? .init()
        micVoiceProcessing =
            try container.decodeIfPresent(
                Bool.self,
                forKey: .micVoiceProcessing
            ) ?? false
        completionHook = try container.decodeIfPresent(
            CompletionHook.self,
            forKey: .completionHook
        )
    }

    public static func decode(_ data: Data) throws -> AppConfiguration {
        let configuration = try JSONDecoder().decode(AppConfiguration.self, from: data)
        guard configuration.schemaVersion == currentSchemaVersion else {
            throw ConfigurationError.unsupportedSchema(configuration.schemaVersion)
        }
        if let hook = configuration.completionHook,
            !hook.executable.hasPrefix("/")
        {
            throw ConfigurationError.hookExecutableMustBeAbsolute(hook.executable)
        }
        guard ["parakeet", "macwhisper"].contains(configuration.transcription.engine) else {
            throw ConfigurationError.unsupportedTranscriptionEngine(
                configuration.transcription.engine
            )
        }
        if configuration.transcription.engine == "macwhisper",
            configuration.transcription.model?.isEmpty != false
        {
            throw ConfigurationError.transcriptionModelRequired("macwhisper")
        }
        if let executable = configuration.transcription.executable,
            !executable.hasPrefix("/")
        {
            throw ConfigurationError.transcriptionExecutableMustBeAbsolute(executable)
        }
        let language = configuration.transcription.language
        let isLanguageValid =
            language == "auto"
            || (language.count == 2 && language.allSatisfy(\.isLetter))
        guard isLanguageValid else {
            throw ConfigurationError.invalidTranscriptionLanguage(language)
        }
        return configuration
    }

    public enum ConfigurationError: Error, Equatable, CustomStringConvertible {
        case unsupportedSchema(Int)
        case hookExecutableMustBeAbsolute(String)
        case unsupportedTranscriptionEngine(String)
        case transcriptionModelRequired(String)
        case transcriptionExecutableMustBeAbsolute(String)
        case invalidTranscriptionLanguage(String)

        public var description: String {
            switch self {
            case .unsupportedSchema(let version):
                return "unsupported configuration schema version \(version)"
            case .hookExecutableMustBeAbsolute(let executable):
                return "completion hook executable must be an absolute path: \(executable)"
            case .unsupportedTranscriptionEngine(let engine):
                return "unsupported transcription engine: \(engine)"
            case .transcriptionModelRequired(let engine):
                return "\(engine) transcription requires an explicit model identifier"
            case .transcriptionExecutableMustBeAbsolute(let executable):
                return "transcription executable must be an absolute path: \(executable)"
            case .invalidTranscriptionLanguage(let language):
                return "invalid transcription language: \(language)"
            }
        }
    }
}

public enum RecordPaths {
    public static func configurationDirectory(home: URL) -> URL {
        home.appendingPathComponent(".config/record", isDirectory: true)
    }

    public static func configurationFile(home: URL) -> URL {
        configurationDirectory(home: home).appendingPathComponent("config.json")
    }

    public static func defaultRecordingsDirectory(home: URL) -> URL {
        home.appendingPathComponent("Recordings", isDirectory: true)
    }

    public static func resolveRecordingsDirectory(
        cliOverride: String?,
        configuration: AppConfiguration,
        home: URL
    ) -> URL {
        let selected = cliOverride ?? configuration.recordingsDirectory
        guard let selected, !selected.isEmpty else {
            return defaultRecordingsDirectory(home: home)
        }

        if selected == "~" {
            return home
        }
        if selected.hasPrefix("~/") {
            return home.appendingPathComponent(String(selected.dropFirst(2)), isDirectory: true)
        }
        return URL(fileURLWithPath: selected, isDirectory: true)
    }
}
