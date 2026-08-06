import Foundation

public enum LocalFileNamePolicy {
    /// Returns true only for one local filename component, never a path.
    public static func isSafeComponent(_ component: String) -> Bool {
        !component.isEmpty
            && component != "."
            && component != ".."
            && !component.hasPrefix("/")
            && !component.contains("/")
            && !component.contains(":")
            && component.unicodeScalars.allSatisfy {
                !CharacterSet.controlCharacters.contains($0)
            }
    }
}
