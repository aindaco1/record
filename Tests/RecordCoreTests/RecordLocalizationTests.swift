import RecordCore
import XCTest

final class RecordLocalizationTests: XCTestCase {
    func testSystemLanguageUsesSupportedPreferenceAndExplicitOverrideWins() {
        XCTAssertEqual(
            InterfaceLanguage.resolve(.system, preferredLanguages: ["fr", "es-MX", "en"]), .spanish)
        XCTAssertEqual(
            InterfaceLanguage.resolve(.system, preferredLanguages: ["en-GB", "es"]), .english)
        XCTAssertEqual(InterfaceLanguage.resolve(.english, preferredLanguages: ["es"]), .english)
        XCTAssertEqual(InterfaceLanguage.resolve(.system, preferredLanguages: ["fr"]), .english)
    }

    func testPackagedNativeResourcesLoadSpanishAndFallbackToSourceText() {
        XCTAssertEqual(L10n.text("Automatic", language: .spanish), "Automático")
        XCTAssertEqual(L10n.text("Automatic", language: .english), "Automatic")
        XCTAssertEqual(
            L10n.text("untranslated fixture", language: .spanish), "untranslated fixture")
    }
}
