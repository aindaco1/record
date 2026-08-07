import Foundation
import RecordCore

enum TranscriptionEngineOption: String, CaseIterable, Sendable {
    case parakeet
    case macwhisper

    var displayName: String {
        switch self {
        case .parakeet: "Parakeet"
        case .macwhisper: "MacWhisper"
        }
    }
}

struct TranscriptionSelection: Equatable, Sendable {
    let engine: TranscriptionEngineOption
    let model: String
    let executable: String?
    let language: String
}

/// One source of truth for user-facing transcription selection. JSON remains
/// the advanced baseline; menu choices are small, typed overrides persisted in
/// the app container without rewriting configuration files.
enum TranscriptionPreferences {
    static let defaultParakeetModel = ParakeetModelID.v3.rawValue
    static let defaultMacWhisperModel = "whisperkit:openai_whisper-small"

    private static let engineKey = "transcription.engine"
    private static let parakeetModelKey = "transcription.parakeet.model"
    private static let macWhisperModelKey = "transcription.macwhisper.model"
    private static let languageKey = "transcription.language"

    static func effectiveSelection(
        configuration: AppConfiguration.Transcription,
        defaults: UserDefaults = .standard
    ) -> TranscriptionSelection {
        let configuredEngine =
            TranscriptionEngineOption(rawValue: configuration.engine) ?? .parakeet
        let engine =
            defaults.string(forKey: engineKey)
            .flatMap(TranscriptionEngineOption.init(rawValue:)) ?? configuredEngine
        let language = defaults.string(forKey: languageKey) ?? configuration.language

        switch engine {
        case .parakeet:
            let configuredModel = configuredEngine == .parakeet ? configuration.model : nil
            return TranscriptionSelection(
                engine: .parakeet,
                model: defaults.string(forKey: parakeetModelKey)
                    ?? configuredModel
                    ?? defaultParakeetModel,
                executable: nil,
                language: language
            )
        case .macwhisper:
            let configuredModel = configuredEngine == .macwhisper ? configuration.model : nil
            return TranscriptionSelection(
                engine: .macwhisper,
                model: defaults.string(forKey: macWhisperModelKey)
                    ?? configuredModel
                    ?? defaultMacWhisperModel,
                executable: configuration.executable,
                language: language
            )
        }
    }

    static func select(
        _ engine: TranscriptionEngineOption,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(engine.rawValue, forKey: engineKey)
        switch engine {
        case .parakeet:
            if defaults.string(forKey: parakeetModelKey) == nil {
                defaults.set(defaultParakeetModel, forKey: parakeetModelKey)
            }
        case .macwhisper:
            if defaults.string(forKey: macWhisperModelKey) == nil {
                defaults.set(defaultMacWhisperModel, forKey: macWhisperModelKey)
            }
        }
    }
}
