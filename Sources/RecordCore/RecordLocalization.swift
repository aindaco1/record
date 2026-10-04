import Foundation

/// Interface language is independent of recognition language and serialized media.
public enum InterfaceLanguage: String, CaseIterable, Sendable {
    case system, english = "en", spanish = "es"

    public static func resolve(_ choice: Self, preferredLanguages: [String]) -> Self {
        guard choice == .system else { return choice }
        for language in preferredLanguages {
            let code = language.lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" }).first
            if code == "es" { return .spanish }
            if code == "en" { return .english }
        }
        return .english
    }
}

public enum L10n {
    public static let preferenceKey = "interface.language"
    /// Resolve once so changing the preference never creates a half-translated window.
    public static let language = InterfaceLanguage.resolve(
        InterfaceLanguage(rawValue: UserDefaults.standard.string(forKey: preferenceKey) ?? "")
            ?? .system,
        preferredLanguages: Locale.preferredLanguages)

    public static func text(_ key: String, language: InterfaceLanguage = language) -> String {
        let code = language == .spanish ? "es" : "en"
        guard let path = Bundle.module.path(forResource: code, ofType: "lproj"),
            let bundle = Bundle(path: path)
        else { return key }
        return bundle.localizedString(forKey: key, value: key, table: "Localizable")
    }

    public static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(
            format: text(key), locale: Locale(identifier: language.rawValue), arguments: arguments)
    }
}
