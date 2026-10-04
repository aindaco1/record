import Foundation
import RecordCore

enum VocabularyPreferences {
    private static let key = "transcription.vocabulary.v1"

    static func current(defaults: UserDefaults = .standard) -> Vocabulary {
        guard let data = defaults.data(forKey: key), data.count <= 256 * 1_024,
            let value = try? JSONDecoder().decode(Vocabulary.self, from: data),
            (try? value.validate()) != nil
        else { return Vocabulary() }
        return value
    }

    static func save(_ vocabulary: Vocabulary, defaults: UserDefaults = .standard) throws {
        try vocabulary.validate()
        let data = try JSONEncoder().encode(vocabulary)
        guard data.count <= 256 * 1_024 else { throw Vocabulary.ValidationError.tooManyTerms }
        defaults.set(data, forKey: key)
    }
}
